#include <ESP8266WiFi.h>
#include <WebSocketsServer.h>

const char* ssid = "HackaTruckIoT";
const char* password = "iothacka";

#define TRIG_PIN D1
#define ECHO_PIN D2

WebSocketsServer webSocket(82);

void setup() {

    Serial.begin(115200);

    pinMode(TRIG_PIN, OUTPUT);
    pinMode(ECHO_PIN, INPUT);

    WiFi.begin(ssid, password);

    Serial.print("Conectando ao WiFi");

    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }

    Serial.println();
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());

    webSocket.begin();
}

float medirDistancia() {

    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);

    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);

    digitalWrite(TRIG_PIN, LOW);

    long duracao = pulseIn(ECHO_PIN, HIGH);

    float distancia = duracao * 0.034 / 2.0;

    return distancia;
}

void loop() {

    webSocket.loop();

    // ===== SOM =====

    int valorSom = analogRead(A0);

    Serial.print("Som: ");
    Serial.println(valorSom);

    String msgSom = "SOM:" + String(valorSom);

    webSocket.broadcastTXT(msgSom);

    // ===== DISTÂNCIA =====

    float distancia = medirDistancia();

    Serial.print("Distancia: ");
    Serial.print(distancia);
    Serial.println(" cm");

    String msgDistancia = "HC:" + String(distancia);

    webSocket.broadcastTXT(msgDistancia);

    delay(500);
}