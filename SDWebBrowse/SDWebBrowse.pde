/*
 * This code is a composition of different codes, using examples
 * from both the LCD and the Ethernet Shield examples from
 * Layada Website.
 * 
 * Copyright (C) 2011 Alessandro Sivieri <sivieri@elet.polimi.it>
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <SdFat.h>
#include <SdFatUtil.h>
#include <SPI.h>
#include <Ethernet.h>
#include <LiquidCrystal.h>
#include <string.h>

#define BUFSIZ 100

/* Set your MAC address */
byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0x34, 0xD2 };
/* Set your IP address */
byte ip[] = {192, 168, 1, 2};

Server server(80);
Sd2Card card;
SdVolume volume;
SdFile root;
SdFile file;
long redCounter = 0;
long greenCounter = 0;

/* Set LCD and LED pins */
LiquidCrystal lcd(9, 8, 7, 6, 5, 3);
int redLed = 2;
int greenLed = 1;

void printCounters() {
    char s1[21];
    char s2[21];
    char t[21];
    unsigned long mls = millis();
    sprintf(s1, "Code 200: %d", greenCounter);
    sprintf(s2, "Code 404: %d", redCounter);
    sprintf(t, "Uptime: %lu ms", mls);
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(s1);
    lcd.setCursor(0, 1);
    lcd.print(s2);
    lcd.setCursor(0, 2);
    lcd.print(t);
}

void ListFiles(Client client, uint8_t flags) {
  dir_t p;
  
  root.rewind();
  client.println("<ul>");
  while (root.readDir(p) > 0) {
    if (p.name[0] == DIR_NAME_FREE) break;
    if (p.name[0] == DIR_NAME_DELETED || p.name[0] == '.') continue;
    if (!DIR_IS_FILE_OR_SUBDIR(&p)) continue;
    client.print("<li><a href=\"");
    for (uint8_t i = 0; i < 11; i++) {
      if (p.name[i] == ' ') continue;
      if (i == 8) {
        client.print('.');
      }
      client.print(p.name[i]);
    }
    client.print("\">");
    for (uint8_t i = 0; i < 11; i++) {
      if (p.name[i] == ' ') continue;
      if (i == 8) {
        client.print('.');
      }
      client.print(p.name[i]);
    }
    client.print("</a>");
    if (DIR_IS_SUBDIR(&p)) {
      client.print('/');
    }
    if (flags & LS_DATE) {
       root.printFatDate(p.lastWriteDate);
       client.print(' ');
       root.printFatTime(p.lastWriteTime);
    }
    if (!DIR_IS_SUBDIR(&p) && (flags & LS_SIZE)) {
      client.print(' ');
      client.print(p.fileSize);
    }
    client.println("</li>");
  }
  client.println("</ul>");
}

char* mimetype(String filename, int index)
{
    if (index == -1) {
        return "text/plain";
    }
    String ext = filename.substring(index + 1);
    if (ext.equalsIgnoreCase("htm")) {
        return "text/html";
    }
    else if (ext.equalsIgnoreCase("css")) {
        return "text/css";
    }
    else if (ext.equalsIgnoreCase("jpg")) {
        return "image/jpeg";
    }
    else if (ext.equalsIgnoreCase("png")) {
        return "image/png";
    }
    else if (ext.equalsIgnoreCase("gif")) {
        return "image/gif";
    }
    else if (ext.equalsIgnoreCase("js")) {
        return "application/javascript";
    }
    
    return "text/plain";
}

void setup() {
  lcd.begin(20, 4);
  lcd.setCursor(0, 0);
  lcd.print("Web server starting");
  lcd.setCursor(0, 1);
  lcd.print("...");
  pinMode(redLed, OUTPUT);
  pinMode(greenLed, OUTPUT);
  digitalWrite(redLed, HIGH);
  digitalWrite(greenLed, HIGH);
  delay(2000);
  digitalWrite(redLed, LOW);
  digitalWrite(greenLed, LOW);
  pinMode(10, OUTPUT);
  digitalWrite(10, HIGH);
  if (!card.init(SPI_HALF_SPEED, 4)) lcd.print("card.init failed!");
  if (!volume.init(&card)) lcd.print("vol.init failed!");
  if (!root.openRoot(&volume)) lcd.print("openRoot failed");
  Ethernet.begin(mac, ip);
  server.begin();
}

void loop()
{
  char clientline[BUFSIZ];
  int index = 0, startExt = 0, startHttp = 0;
  unsigned long currentMillis = 0;
  /* String objects are not particularly performant,
   * change this if you want more performances, and
   * use character arrays.
   */
  String clientlineString;
  String filenameString;
  
  Client client = server.available();
  if (client) {
    boolean current_line_is_blank = true;
    index = 0;
    while (client.connected()) {
      if (client.available()) {
        char c = client.read();
        if (c != '\n' && c != '\r') {
          clientline[index] = c;
          index++;
          if (index >= BUFSIZ) 
            index = BUFSIZ -1;
          continue;
        }
        clientline[index] = 0;
        clientlineString = String(clientline);
        startHttp = clientlineString.indexOf("HTTP");
        if (strstr(clientline, "GET / ") != 0) {
          ++greenCounter;
          client.println("HTTP/1.1 200 OK");
          client.println("Content-Type: text/html");
          client.println();
          client.println("<h2>Files:</h2>");
          ListFiles(client, LS_SIZE);
        }
        else if (strstr(clientline, "GET /") != 0) {
          char *filename;
          filename = clientline + 5;
          (strstr(clientline, " HTTP"))[0] = 0;
          filenameString = clientlineString.substring(5, startHttp - 1);
          startExt = filenameString.lastIndexOf('.');
          if (! file.open(&root, filename, O_READ)) {
            ++redCounter;
            digitalWrite(redLed, HIGH);
            client.println("HTTP/1.1 404 Not Found");
            client.println("Content-Type: text/html");
            client.println();
            client.println("<h2>File Not Found!</h2>");
            break;
          }
          ++greenCounter;
          digitalWrite(greenLed, HIGH);
          client.println("HTTP/1.1 200 OK");
          client.print("Content-Type: ");
          client.println(mimetype(filenameString, startExt));
          client.println();
          int16_t c;
          while ((c = file.read()) > 0) {
              client.print((char)c);
          }
          file.close();
        }
        else {
          digitalWrite(redLed, HIGH);
          client.println("HTTP/1.1 404 Not Found");
          client.println("Content-Type: text/html");
          client.println();
          client.println("<h2>File Not Found!</h2>");
        }
        break;
      }
    }
    delay(1);
    client.stop();
    /* These delays slow performances, avoid using LEDs if,
     * again, you seek them.
     */
    delay(50);
    digitalWrite(redLed, LOW);
    digitalWrite(greenLed, LOW);
    if (greenCounter % 5 == 0) {
        printCounters();
    }
  }
}

