//
//  WebSocket.swift
//  HackaHomeFinal
//
//  Created by Turma02-18 on 18/06/26.
//

import SwiftUI
import Foundation
import Combine

struct LeituraRFID: Identifiable {
    let id = UUID()
    let data = Date()
    let uid: String
    let autorizado: Bool
}

class RFIDViewModel: ObservableObject {
    
    @Published var uidAtual = ""
    @Published var acessoLiberado = false
    @Published var status = "Aguardando tag RFID..."
    @Published var valorGas = 0
    
    private var webSocketTask: URLSessionWebSocketTask?
    
    // IP da sua ESP
    let url = URL(string: "ws://192.168.128.112:81")! //esp gas e rfid
    
    // Coloque aqui o UID da sua tag autorizada
    let manager = MoradoresManager()
    func conectar() {
        guard webSocketTask == nil else { return }
        
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        status = "Conectado. Aproxime a tag..."
        
        receber()
    }
    
    func desconectar() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
    
    private func receber() {
        webSocketTask?.receive { [weak self] result in
            
            guard let self = self else { return }
            
            switch result {
                
            case .success(let message):
                
                switch message {
                    
                case .string(let texto):
                    self.processarMensagem(texto)
                    
                case .data(let data):
                    if let texto = String(data: data, encoding: .utf8) {
                        self.processarMensagem(texto)
                    }
                    
                @unknown default:
                    break
                }
                
                self.receber()
                
            case .failure(let erro):
                print("Erro WebSocket:", erro)
                
                DispatchQueue.main.async {
                    self.status = "Erro na conexão. Tentando reconectar..."
                    self.webSocketTask = nil
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.conectar()
                }
            }
        }
    }
    
    private func processarMensagem(_ texto: String) {
        
        print("Mensagem recebida:", texto)
        
        let mensagem = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Se for número, é valor do gás. Então ignora no RFID.
        if let valorGas = Int(mensagem) {
            DispatchQueue.main.async {
                self.valorGas = valorGas
            }
            return
        }
        
        // Se não for número, trata como UID RFID
        let uidRecebido = mensagem
        let manager = MoradoresManager()
        let morador = manager.buscar(uid: uidRecebido)
        let autorizado = morador != nil
        
        DispatchQueue.main.async {
            self.uidAtual = uidRecebido
            self.acessoLiberado = autorizado
            
            if let morador = morador {
                self.status = "Acesso liberado: \(morador.nome)"
            } else {
                self.status = "Tag não autorizada"
            }
        }}
    
    
    class SomMovimentoViewModel: ObservableObject {
        
        @Published var valorSom = 0
        @Published var distancia = 0.0
        @Published var status = "Conectando sensores..."
        
        private var webSocketTask: URLSessionWebSocketTask?
        
        let url = URL(string: "ws://192.168.128.101:82")!
        
        func conectar() {
            guard webSocketTask == nil else { return }
            
            webSocketTask = URLSession.shared.webSocketTask(with: url)
            webSocketTask?.resume()
            
            status = "Sensores conectados"
            receber()
        }
        
        func desconectar() {
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
        }
        
        private func receber() {
            webSocketTask?.receive { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let texto):
                        self.processarMensagem(texto)
                    case .data(let data):
                        if let texto = String(data: data, encoding: .utf8) {
                            self.processarMensagem(texto)
                        }
                    @unknown default:
                        break
                    }
                    self.receber()
                    
                case .failure(let erro):
                    print("Erro Som/Movimento:", erro)
                    DispatchQueue.main.async {
                        self.status = "Erro na conexão Som/Movimento"
                        self.webSocketTask = nil
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.conectar()
                    }
                }
            }
        }
        
        private func processarMensagem(_ texto: String) {
            let mensagem = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            print("ESP2:", mensagem)
            
            if mensagem.starts(with: "SOM:") {
                let valor = mensagem.replacingOccurrences(of: "SOM:", with: "")
                DispatchQueue.main.async {
                    self.valorSom = Int(valor) ?? 0
                }
            }
            
            if mensagem.starts(with: "HC:") {
                let valor = mensagem.replacingOccurrences(of: "HC:", with: "")
                DispatchQueue.main.async {
                    self.distancia = Double(valor) ?? 0.0
                }
            }
        }
    }
}


