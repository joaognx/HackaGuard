/*#include <ESP8266WiFi.h>
#include <WebSocketsServer.h>

const char* ssid = "HackaTruckIoT";
const char* password = "iothacka";

WebSocketsServer webSocket(81);

void setup() {
  Serial.begin(115200);

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
  }

  Serial.print("IP: ");
  Serial.println(WiFi.localIP());

  webSocket.begin();
}

void loop() {
  webSocket.loop();

  int umidade = analogRead(A0);

  String json = "{\"umidade\":" + String(umidade) + "}";
   Serial.print("IP: ");
     Serial.println(WiFi.localIP());

   

  webSocket.broadcastTXT(json);

  Serial.println(json);

  delay(2000);
}*/

#include <ESP8266WiFi.h>
#include <WebSocketsServer.h>
#include <SPI.h>
#include <MFRC522.h>

const char* ssid = "HackaTruckIoT";
const char* password = "iothacka";

#define RST_PIN D4
#define SS_PIN  D8

MFRC522 mfrc522(SS_PIN, RST_PIN);
WebSocketsServer webSocket = WebSocketsServer(81);

void webSocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
    switch(type) {
        case WStype_DISCONNECTED:
            Serial.printf("[%u] Desconectado!\n", num);
            break;

        case WStype_CONNECTED: {
            IPAddress ip = webSocket.remoteIP(num);
            Serial.printf("[%u] Conectado de %d.%d.%d.%d\n", num, ip[0], ip[1], ip[2], ip[3]);
            break;
        }

        case WStype_TEXT:
            Serial.printf("[%u] Mensagem recebida: %s\n", num, payload);
            break;
    }
}

void setup() {

    Serial.begin(115200);

    SPI.begin();
    mfrc522.PCD_Init();

    WiFi.begin(ssid, password);

    Serial.print("Conectando ao Wi-Fi");
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }

    Serial.println("\nWiFi conectado! IP:");
    Serial.println(WiFi.localIP());

    webSocket.begin();
    webSocket.onEvent(webSocketEvent);

    Serial.println("Aguardando conexões WebSocket...");
}

void loop() {

    webSocket.loop();

    int valorGas = analogRead(A0);

    Serial.print("Gas: ");
    Serial.println(valorGas);

    // Envia só o valor do gás pelo WebSocket
    String gasString = String(valorGas);
    webSocket.broadcastTXT(gasString);

    /*int valorSom = analogRead(A0);

    Serial.print("Som: ");
    Serial.println(valorSom);

    String somString = String(valorSom);
    webSocket.broadcastTXT(somString);*/

    delay(500);

    if (!mfrc522.PICC_IsNewCardPresent()) {
        return;
    }

    if (!mfrc522.PICC_ReadCardSerial()) {
        return;
    }

    String uidString = "";

    for (byte i = 0; i < mfrc522.uid.size; i++) {
        uidString += String(mfrc522.uid.uidByte[i] < 0x10 ? "0" : "");
        uidString += String(mfrc522.uid.uidByte[i], HEX);

        if (i < mfrc522.uid.size - 1) {
            uidString += " ";
        }
    }

    uidString.toUpperCase();

    Serial.print("Tag lida: ");
    Serial.println(uidString);

    // Envia o UID da tag também pelo WebSocket
    webSocket.broadcastTXT(uidString);

    mfrc522.PICC_HaltA();
    mfrc522.PCD_StopCrypto1();

    delay(1000);
}