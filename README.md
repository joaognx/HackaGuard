# 🛡️ HackaGuard

HackaGuard é um sistema inteligente de monitoramento residencial desenvolvido durante o **HackaTruck MakerSpace**. O projeto integra **Internet das Coisas (IoT)**, desenvolvimento **iOS** e **Node-RED** para oferecer monitoramento em tempo real, controle de acesso e registro de ocorrências.

O sistema utiliza dispositivos ESP8266 conectados a sensores para detectar eventos na residência e enviar as informações em tempo real para um aplicativo iOS por meio de WebSockets.

---

## 📱 Funcionalidades

- 🔐 Controle de acesso utilizando RFID
- 👤 Cadastro de moradores autorizados
- 🌫️ Detecção de vazamento de gás
- 🔊 Monitoramento de ruídos
- 📏 Detecção de movimento com sensor ultrassônico
- 📡 Comunicação em tempo real via WebSockets
- 📲 Aplicativo desenvolvido em SwiftUI
- 🔔 Notificações locais para alertas
- 📋 Histórico de ocorrências
- ☁️ Integração com Node-RED

---

## 🏗️ Arquitetura

```
          +---------------------+
          |    ESP8266 #1       |
          |  RFID + Sensor Gás  |
          +----------+----------+
                     |
                WebSocket (:81)
                     |
                     |
+--------------------+--------------------+
|                                         |
|          Aplicativo iOS                 |
|              SwiftUI                    |
|                                         |
|  • Dashboard                            |
|  • Controle de acesso                   |
|  • Sensores em tempo real               |
|  • Histórico                            |
|  • Notificações                         |
+--------------------+--------------------+
                     |
                HTTP REST
                     |
             +-------+-------+
             |    Node-RED   |
             | Histórico API |
             +-------+-------+
                     |
                WebSocket (:82)
                     |
          +----------+----------+
          |    ESP8266 #2       |
          | Som + Ultrassônico  |
          +---------------------+
```

---

## 🛠️ Tecnologias

### Mobile
- SwiftUI
- Combine
- URLSession
- WebSockets
- UserNotifications

### IoT
- ESP8266 (NodeMCU)
- Arduino IDE
- RFID RC522
- MQ-3
- Sensor de Som
- HC-SR04

### Backend
- Node-RED
- HTTP REST
- JSON

---

## 🚀 Como executar

### Clone o repositório

```bash
git clone https://github.com/joaognx/HackaGuard.git
```

### Configure os ESP8266

Atualize o SSID e a senha da rede Wi-Fi:

```cpp
const char* ssid = "SEU_WIFI";
const char* password = "SUA_SENHA";
```

### Configure os endereços IP

No aplicativo iOS, altere os IPs para os dispositivos da sua rede:

```swift
ws://IP_DA_ESP1:81
ws://IP_DA_ESP2:82

http://IP_DO_NODE_RED:1880/postCasa
http://IP_DO_NODE_RED:1880/getCasa
```

### Execute o Node-RED

Importe os fluxos disponíveis no projeto e inicie o servidor.

### Execute o aplicativo

Abra o projeto no Xcode e execute em um dispositivo iOS.

---

## 📂 Estrutura do projeto

```
HackaGuard
│
├── 📱 Aplicativo iOS (SwiftUI)
├── 🔌 ESP8266 RFID + Gás
├── 🔌 ESP8266 Som + Distância
├── 🌐 Fluxos Node-RED
└── 📖 README.md
```
---

## 👨‍💻 Desenvolvedores

**João Gabriel Nunes, Arthur Sobreira Alexandrinho, José Weides Piauilino, Andrew Lopes Tavares**

Desenvolvido durante o **HackaTruck MakerSpace**, programa de capacitação promovido pela IBM em parceria com instituições de ensino, com foco em desenvolvimento iOS, Internet das Coisas (IoT), computação em nuvem e inovação tecnológica.
