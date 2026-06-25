//
//  FrontEnd.swift
//  HackaGuard
//
//  Created by Turma02-18 on 23/06/26.
//

import SwiftUI
import Combine

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        
        switch hex.count {
        case 3:
            (a, r, g, b) = (
                255,
                (int >> 8) * 17,
                (int >> 4 & 0xF) * 17,
                (int & 0xF) * 17
            )
        case 6:
            (a, r, g, b) = (
                255,
                int >> 16,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        case 8:
            (a, r, g, b) = (
                int >> 24,
                int >> 16 & 0xFF,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct AppColors {
    static let azulNoite = Color(hex: "#0B1220")
    static let azulMarca = Color(hex: "#2563EB")
    static let azulEscuro = Color(hex: "#1E3A8A")
    static let azulSoft = Color(hex: "#DBEAFE")
    
    static let verdeSeguro = Color(hex: "#16A34A")
    static let amareloAtencao = Color(hex: "#F59E0B")
    static let vermelhoAlerta = Color(hex: "#DC2626")
    
    static let fundoClaro = Color(hex: "#F8FAFC")
    static let cardClaro = Color(hex: "#F1F5F9")
    static let textoPrincipal = Color(hex: "#0F172A")
    static let textoSecundario = Color(hex: "#64748B")
    static let branco = Color.white
}

struct HackaGuardData {
    var status: String
    var mensagem: String
    var usuario: String
    var rfidAutorizado: Bool
    var distancia: Double
    var gas: Int
    var som: Int
    var ultimoEvento: String
}

struct EventoHistorico: Identifiable {
    let id = UUID()
    var tipo: String
    var titulo: String
    var descricao: String
    var horario: String
    var cor: Color
    var icone: String
}

class HackaGuardViewModel: ObservableObject {
    private let service = Service()
    private var ultimoEnvioAlerta: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()

    let urlGetHistorico = URL(string: "http://192.168.128.52:1880/getCasa")!

    let urlPostHistorico = URL(string: "http://192.168.128.52:1880/postCasa")!
    @Published var sistemaArmado: Bool = true
    
    @Published var data = HackaGuardData(
        status: "Casa segura",
        mensagem: "Todos os sensores estão funcionando normalmente",
        usuario: "Aguardando RFID",
        rfidAutorizado: false,
        distancia: 0,
        gas: 0,
        som: 0,
        ultimoEvento: "Sistema iniciado"
    )
    
    @Published var historico: [EventoHistorico] = []
    
    private var wsESP1: URLSessionWebSocketTask?
    private var wsESP2: URLSessionWebSocketTask?
    
    let urlESP1 = URL(string: "ws://192.168.128.101:81")! // RFID + gás
    let urlESP2 = URL(string: "ws://192.168.128.104:82")! // som + distância
    
    let tagAutorizada = "F3 1C 40 14"
    func buscarHistoricoBackend() {
        service.fetchHistorico(url: urlGetHistorico)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                print("GET histórico:", completion)
            }) { ocorrencias in
                self.historico = ocorrencias.map { item in
                    EventoHistorico(
                        tipo: item.Tipo ?? "Alerta",
                        titulo: item.Tipo ?? "Ocorrência",
                        descricao: "Data: \(item.Data ?? "-")",
                        horario: item.Hora ?? "--:--",
                        cor: AppColors.vermelhoAlerta,
                        icone: "exclamationmark.triangle.fill"
                    )
                }
            }
            .store(in: &cancellables)
    }
    
    func dataAtual() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: Date())
    }

    func podeEnviarAlerta(tipo: String) -> Bool {
        let agora = Date()
        
        if let ultimo = ultimoEnvioAlerta[tipo],
           agora.timeIntervalSince(ultimo) < 10 {
            return false
        }
        
        ultimoEnvioAlerta[tipo] = agora
        return true
    }

    func enviarAlertaBackend(tipo: String) {
        guard podeEnviarAlerta(tipo: tipo) else { return }
        
        let ocorrencia = Historico(
            id: UUID().uuidString,
            Tipo: tipo,
            Data: dataAtual(),
            Hora: horaAtual()
        )
        
        service.postOcorrencia(url: urlPostHistorico, Ocorrencia: ocorrencia) { sucesso in
            if sucesso {
                print("Alerta enviado para o Node-RED:", tipo)
            } else {
                print("Erro ao enviar alerta:", tipo)
            }
        }
    }
    
    func conectarWebSockets() {
        conectarESP1()
        conectarESP2()
    }
    
    func desconectarWebSockets() {
        wsESP1?.cancel(with: .normalClosure, reason: nil)
        wsESP2?.cancel(with: .normalClosure, reason: nil)
        wsESP1 = nil
        wsESP2 = nil
    }
    
    private func conectarESP1() {
        wsESP1 = URLSession.shared.webSocketTask(with: urlESP1)
        wsESP1?.resume()
        receberESP1()
    }
    
    private func conectarESP2() {
        wsESP2 = URLSession.shared.webSocketTask(with: urlESP2)
        wsESP2?.resume()
        receberESP2()
    }
    
    private func receberESP1() {
        wsESP1?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                if case .string(let texto) = message {
                    self.processarESP1(texto)
                }
                self.receberESP1()
                
            case .failure(let erro):
                print("Erro ESP1:", erro)
                self.wsESP1 = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.conectarESP1()
                }
            }
        }
    }
    
    private func receberESP2() {
        wsESP2?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                if case .string(let texto) = message {
                    self.processarESP2(texto)
                }
                self.receberESP2()
                
            case .failure(let erro):
                print("Erro ESP2:", erro)
                self.wsESP2 = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.conectarESP2()
                }
            }
        }
    }
    
    private func processarESP1(_ texto: String) {
        let mensagem = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        print("ESP1:", mensagem)
        
        if mensagem.hasPrefix("GAS:") {
            let valor = mensagem.replacingOccurrences(of: "GAS:", with: "")
            let gas = Int(valor) ?? 0
            
            DispatchQueue.main.async {
                self.data.gas = gas
                
                if gas > 700 {
                    self.data.status = "Alerta de gás"
                    self.data.mensagem = "Nível alto de gás/vapor detectado"
                    self.data.ultimoEvento = "Alerta de gás às \(self.horaAtual())"

                    self.enviarAlertaBackend(tipo: "Alerta de gás")
                }            }
            return
        }
        
        let uid = mensagem
        let autorizado = uid == tagAutorizada
        
        DispatchQueue.main.async {
            self.data.rfidAutorizado = autorizado
            self.data.usuario = autorizado ? "João Gabriel" : "Tag desconhecida"
            self.data.ultimoEvento = autorizado ? "Acesso autorizado às \(self.horaAtual())" : "Acesso negado às \(self.horaAtual())"
            
            self.adicionarEvento(
                tipo: "Acesso",
                titulo: autorizado ? "Entrada autorizada" : "Entrada negada",
                descricao: "UID: \(uid)",
                cor: autorizado ? AppColors.verdeSeguro : AppColors.vermelhoAlerta,
                icone: autorizado ? "person.badge.key.fill" : "xmark.shield.fill"
            )
        }
    }
    
    private func processarESP2(_ texto: String) {
        let mensagem = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        print("ESP2:", mensagem)
        
        if mensagem.hasPrefix("SOM:") {

            let valor = mensagem.replacingOccurrences(of: "SOM:", with: "")
            let som = Int(valor) ?? 0

            DispatchQueue.main.async {

                self.data.som = som

                if som > 600 {
                    self.enviarAlertaBackend(tipo: "Alerta de som")
                }
            }
        }
        
        if mensagem.hasPrefix("HC:") {

            let valor = mensagem.replacingOccurrences(of: "HC:", with: "")
            let distancia = Double(valor) ?? 0.0

            DispatchQueue.main.async {

                self.data.distancia = distancia

                if distancia < 30 && distancia > 0 {
                    self.enviarAlertaBackend(tipo: "Movimento detectado")
                }
            }
        }
    }

    func corStatus() -> Color {
        let texto = data.status.lowercased()
        if texto.contains("alerta") || texto.contains("perigo") {
            return AppColors.vermelhoAlerta
        } else if texto.contains("atenção") {
            return AppColors.amareloAtencao
        } else {
            return AppColors.verdeSeguro
        }
    }
    
    func iconeStatus() -> String {
        let texto = data.status.lowercased()
        if texto.contains("alerta") || texto.contains("perigo") {
            return "exclamationmark.triangle.fill"
        } else if texto.contains("atenção") {
            return "exclamationmark.circle.fill"
        } else {
            return "checkmark.shield.fill"
        }
    }
    
    func horaAtual() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
    
    func adicionarEvento(tipo: String, titulo: String, descricao: String, cor: Color, icone: String) {
        historico.insert(
            EventoHistorico(
                tipo: tipo,
                titulo: titulo,
                descricao: descricao,
                horario: horaAtual(),
                cor: cor,
                icone: icone
            ),
            at: 0
        )
    }
}

struct ContentFrontView: View {
    @StateObject private var viewModel = HackaGuardViewModel()
    @StateObject private var rfid = RFIDViewModel()
    @StateObject private var sensores = SomMovimentoViewModel()
    
    var body: some View {
        Group {
            if rfid.acessoLiberado {
                MainTabView()
                    .environmentObject(viewModel)
            } else {
                TelaBloqueioRFID(rfid: rfid)
            }
        }
        .onAppear {
            rfid.conectar()
            sensores.conectar()
            viewModel.buscarHistoricoBackend()
        }
        .onDisappear {
            rfid.desconectar()
            sensores.desconectar()
        }
        .onReceive(rfid.$valorGas) { valor in
            viewModel.data.gas = valor

            if valor > 650 {
                viewModel.enviarAlertaBackend(tipo: "Alerta de gás")
            }
        }
        .onReceive(rfid.$acessoLiberado) { autorizado in
            viewModel.data.rfidAutorizado = autorizado
            viewModel.data.usuario = autorizado ? "João Gabriel" : "Aguardando RFID"
        }
        .onReceive(sensores.$valorSom) { valor in
            viewModel.data.som = valor

            if valor > 600 {
                viewModel.enviarAlertaBackend(tipo: "Alerta de som")
            }
        }
        .onReceive(sensores.$distancia) { valor in
            viewModel.data.distancia = valor

            if valor < 30 && valor > 0 {
                viewModel.enviarAlertaBackend(tipo: "Movimento detectado")
            }
        }
    }
}

struct TelaBloqueioRFID: View {
    @ObservedObject var rfid: RFIDViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 90))
                .foregroundColor(AppColors.vermelhoAlerta)
            
            Text("HackaGuard")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Aproxime sua tag RFID para desbloquear")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text(rfid.status)
                .foregroundColor(AppColors.textoSecundario)
            
            if !rfid.uidAtual.isEmpty {
                Text("Última tag: \(rfid.uidAtual)")
                    .font(.caption)
                    .foregroundColor(AppColors.textoSecundario)
            }
            
            Button("Modo cadastro") {
                rfid.acessoLiberado = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.fundoClaro)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppColors.azulNoite,
                    AppColors.azulEscuro,
                    AppColors.azulMarca
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(AppColors.branco.opacity(0.12))
                        .frame(width: 130, height: 130)
                    
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 80))
                        .foregroundColor(AppColors.branco)
                }
                
                Text("HackaGuard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.branco)
                
                Text("Segurança residencial inteligente")
                    .font(.headline)
                    .foregroundColor(AppColors.branco.opacity(0.85))
                
                ProgressView()
                    .tint(AppColors.branco)
                    .padding(.top, 20)
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Início")
                }
            
            SensoresView()
                .tabItem {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    Text("Sensores")
                }
            
            RFIDView()
                .tabItem {
                    Image(systemName: "person.badge.key.fill")
                    Text("RFID")
                }
            
            HistoricoView()
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("Histórico")
                }
        }
        .accentColor(AppColors.azulMarca)
    }
}

struct DashboardView: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    HeaderHomeView()
                    StatusCard()
                    ModoSegurancaCard()
                    UltimoEventoCard()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sensores ativos")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.textoPrincipal)
                        
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: 16
                        ) {
                            NavigationLink(destination: RFIDView()) {
                                SensorResumoCard(
                                    titulo: "RFID",
                                    valor: viewModel.data.rfidAutorizado ? "Autorizado" : "Não lido",
                                    status: viewModel.data.usuario,
                                    icone: "person.badge.key.fill",
                                    cor: viewModel.data.rfidAutorizado ? AppColors.verdeSeguro : AppColors.amareloAtencao,
                                    progresso: viewModel.data.rfidAutorizado ? 1.0 : 0.4
                                )
                            }
                            
                            NavigationLink(destination: DistanciaDetalheView()) {
                                SensorResumoCard(
                                    titulo: "Distância",
                                    valor: "\(Int(viewModel.data.distancia)) cm",
                                    status: viewModel.data.distancia < 50 ? "Movimento" : "Normal",
                                    icone: "ruler.fill",
                                    cor: viewModel.data.distancia < 50 ? AppColors.amareloAtencao : AppColors.verdeSeguro,
                                    progresso: min(viewModel.data.distancia / 200, 1.0)
                                )
                            }
                            
                            NavigationLink(destination: GasDetalheView()) {
                                SensorResumoCard(
                                    titulo: "Gás/Vapor",
                                    valor: "\(viewModel.data.gas)",
                                    status: viewModel.data.gas > 700 ? "Perigo" : viewModel.data.gas > 400 ? "Atenção" : "Normal",
                                    icone: "wind",
                                    cor: viewModel.data.gas > 700 ? AppColors.vermelhoAlerta : viewModel.data.gas > 400 ? AppColors.amareloAtencao : AppColors.verdeSeguro,
                                    progresso: min(Double(viewModel.data.gas) / 1000, 1.0)
                                )
                            }
                            
                            NavigationLink(destination: SomDetalheView()) {
                                SensorResumoCard(
                                    titulo: "Som",
                                    valor: "\(viewModel.data.som)",
                                    status: viewModel.data.som > 600 ? "Alto" : viewModel.data.som > 350 ? "Moderado" : "Baixo",
                                    icone: "waveform",
                                    cor: viewModel.data.som > 600 ? AppColors.vermelhoAlerta : viewModel.data.som > 350 ? AppColors.amareloAtencao : AppColors.verdeSeguro,
                                    progresso: min(Double(viewModel.data.som) / 1000, 1.0)
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.fundoClaro)
            .navigationTitle("HackaGuard")
        }
    }
}

struct HeaderHomeView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bem-vindo")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textoSecundario)
                
                Text("Central de monitoramento")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.textoPrincipal)
            }
            
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppColors.azulSoft)
                    .frame(width: 52, height: 52)
                
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2)
                    .foregroundColor(AppColors.azulMarca)
            }
        }
    }
}

struct StatusCard: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: viewModel.iconeStatus())
                .font(.system(size: 60))
                .foregroundColor(AppColors.branco)
            
            Text(viewModel.data.status)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppColors.branco)
                .multilineTextAlignment(.center)
            
            Text(viewModel.data.mensagem)
                .font(.body)
                .foregroundColor(AppColors.branco.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            LinearGradient(
                colors: [
                    viewModel.corStatus(),
                    viewModel.corStatus().opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(26)
        .shadow(color: viewModel.corStatus().opacity(0.25), radius: 8, x: 0, y: 5)
    }
}

struct ModoSegurancaCard: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(viewModel.sistemaArmado ? AppColors.verdeSeguro.opacity(0.13) : AppColors.amareloAtencao.opacity(0.13))
                    .frame(width: 52, height: 52)
                
                Image(systemName: viewModel.sistemaArmado ? "lock.shield.fill" : "lock.open.fill")
                    .font(.title2)
                    .foregroundColor(viewModel.sistemaArmado ? AppColors.verdeSeguro : AppColors.amareloAtencao)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Modo de segurança")
                    .font(.headline)
                    .foregroundColor(AppColors.textoPrincipal)
                
                Text(viewModel.sistemaArmado ? "Sistema armado" : "Sistema desarmado")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textoSecundario)
            }
            
            Spacer()
            
            Toggle("", isOn: $viewModel.sistemaArmado)
                .labelsHidden()
                .tint(AppColors.azulMarca)
        }
        .padding()
        .background(AppColors.branco)
        .cornerRadius(20)
    }
}

struct UltimoEventoCard: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "clock.fill")
                .font(.title2)
                .foregroundColor(AppColors.azulMarca)
                .frame(width: 45, height: 45)
                .background(AppColors.azulSoft)
                .cornerRadius(14)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Último evento")
                    .font(.headline)
                    .foregroundColor(AppColors.textoPrincipal)
                
                Text(viewModel.data.ultimoEvento)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textoSecundario)
            }
            
            Spacer()
        }
        .padding()
        .background(AppColors.branco)
        .cornerRadius(20)
    }
}

struct SensorResumoCard: View {
    var titulo: String
    var valor: String
    var status: String
    var icone: String
    var cor: Color
    var progresso: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icone)
                    .font(.title2)
                    .foregroundColor(cor)
                
                Spacer()
                
                Circle()
                    .fill(cor)
                    .frame(width: 10, height: 10)
            }
            
            Text(titulo)
                .font(.headline)
                .foregroundColor(AppColors.textoPrincipal)
            
            Text(valor)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textoPrincipal)
            
            Text(status)
                .font(.caption)
                .foregroundColor(AppColors.textoSecundario)
            
            ProgressView(value: progresso)
                .tint(cor)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .background(AppColors.branco)
        .cornerRadius(22)
    }
}

struct SensoresView: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var body: some View {
        NavigationView {
            List {
                Section("Sensores ambientais") {
                    NavigationLink(destination: GasDetalheView()) {
                        SensorLinha(
                            nome: "Sensor de Gás/Vapor",
                            valor: "\(viewModel.data.gas)",
                            status: viewModel.data.gas > 700 ? "Perigo" : viewModel.data.gas > 400 ? "Atenção" : "Normal",
                            icone: "wind",
                            cor: viewModel.data.gas > 700 ? AppColors.vermelhoAlerta : viewModel.data.gas > 400 ? AppColors.amareloAtencao : AppColors.verdeSeguro
                        )
                    }
                    
                    NavigationLink(destination: SomDetalheView()) {
                        SensorLinha(
                            nome: "Sensor de Som",
                            valor: "\(viewModel.data.som)",
                            status: viewModel.data.som > 600 ? "Alto" : viewModel.data.som > 350 ? "Moderado" : "Baixo",
                            icone: "waveform",
                            cor: viewModel.data.som > 600 ? AppColors.vermelhoAlerta : viewModel.data.som > 350 ? AppColors.amareloAtencao : AppColors.verdeSeguro
                        )
                    }
                }
                
                Section("Segurança de entrada") {
                    NavigationLink(destination: DistanciaDetalheView()) {
                        SensorLinha(
                            nome: "Sensor de Distância",
                            valor: "\(Int(viewModel.data.distancia)) cm",
                            status: viewModel.data.distancia < 50 ? "Movimento" : "Normal",
                            icone: "ruler.fill",
                            cor: viewModel.data.distancia < 50 ? AppColors.amareloAtencao : AppColors.verdeSeguro
                        )
                    }
                    
                    NavigationLink(destination: RFIDView()) {
                        SensorLinha(
                            nome: "RFID",
                            valor: viewModel.data.usuario,
                            status: viewModel.data.rfidAutorizado ? "Autorizado" : "Não autorizado",
                            icone: "person.badge.key.fill",
                            cor: viewModel.data.rfidAutorizado ? AppColors.verdeSeguro : AppColors.amareloAtencao
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.fundoClaro)
            .navigationTitle("Sensores")
        }
    }
}

struct SensorLinha: View {
    var nome: String
    var valor: String
    var status: String
    var icone: String
    var cor: Color
    
    var body: some View {
        HStack {
            Image(systemName: icone)
                .font(.title2)
                .foregroundColor(cor)
                .frame(width: 42)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(nome)
                    .font(.headline)
                    .foregroundColor(AppColors.textoPrincipal)
                
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textoSecundario)
            }
            
            Spacer()
            
            Text(valor)
                .font(.headline)
                .foregroundColor(cor)
        }
        .padding(.vertical, 8)
    }
}

struct GasDetalheView: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var gasStatus: String {
        if viewModel.data.gas > 700 {
            return "Perigo: nível alto de gás/vapor"
        } else if viewModel.data.gas > 400 {
            return "Atenção: nível moderado"
        } else {
            return "Nível normal"
        }
    }
    
    var gasColor: Color {
        if viewModel.data.gas > 700 {
            return AppColors.vermelhoAlerta
        } else if viewModel.data.gas > 400 {
            return AppColors.amareloAtencao
        } else {
            return AppColors.verdeSeguro
        }
    }
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            Image(systemName: "wind")
                .font(.system(size: 90))
                .foregroundColor(gasColor)
            
            Text("Gás/Vapor")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textoPrincipal)
            
            Text("\(viewModel.data.gas)")
                .font(.system(size: 62, weight: .bold))
                .foregroundColor(gasColor)
            
            Text(gasStatus)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.textoPrincipal)
                .padding(.horizontal)
            
            ProgressView(value: Double(viewModel.data.gas), total: 1000)
                .tint(gasColor)
                .padding(.horizontal)
            
            Text("O sensor MQ-3 está sendo usado no protótipo para detectar vapores no ambiente.")
                .font(.footnote)
                .foregroundColor(AppColors.textoSecundario)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
        }
        .padding()
        .background(AppColors.fundoClaro)
        .navigationTitle("Gás")
    }
}

struct SomDetalheView: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var somStatus: String {
        if viewModel.data.som > 600 {
            return "Barulho alto detectado"
        } else if viewModel.data.som > 350 {
            return "Barulho moderado"
        } else {
            return "Ambiente silencioso"
        }
    }
    
    var somColor: Color {
        if viewModel.data.som > 600 {
            return AppColors.vermelhoAlerta
        } else if viewModel.data.som > 350 {
            return AppColors.amareloAtencao
        } else {
            return AppColors.verdeSeguro
        }
    }
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            Image(systemName: "waveform")
                .font(.system(size: 90))
                .foregroundColor(somColor)
            
            Text("Som")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textoPrincipal)
            
            Text("\(viewModel.data.som)")
                .font(.system(size: 62, weight: .bold))
                .foregroundColor(somColor)
            
            Text(somStatus)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.textoPrincipal)
                .padding(.horizontal)
            
            ProgressView(value: Double(viewModel.data.som), total: 1000)
                .tint(somColor)
                .padding(.horizontal)
            
            Text("Esse sensor pode indicar barulhos suspeitos, batidas ou movimentações incomuns.")
                .font(.footnote)
                .foregroundColor(AppColors.textoSecundario)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
        }
        .padding()
        .background(AppColors.fundoClaro)
        .navigationTitle("Som")
    }
}

struct DistanciaDetalheView: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    
    var distanciaStatus: String {
        if viewModel.data.distancia < 30 {
            return "Pessoa muito próxima da entrada"
        } else if viewModel.data.distancia < 60 {
            return "Movimento detectado"
        } else {
            return "Nenhum movimento próximo"
        }
    }
    
    var distanciaColor: Color {
        if viewModel.data.distancia < 30 {
            return AppColors.vermelhoAlerta
        } else if viewModel.data.distancia < 60 {
            return AppColors.amareloAtencao
        } else {
            return AppColors.verdeSeguro
        }
    }
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            Image(systemName: "ruler.fill")
                .font(.system(size: 90))
                .foregroundColor(distanciaColor)
            
            Text("Distância")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textoPrincipal)
            
            Text("\(Int(viewModel.data.distancia)) cm")
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(distanciaColor)
            
            Text(distanciaStatus)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.textoPrincipal)
                .padding(.horizontal)
            
            ProgressView(value: viewModel.data.distancia, total: 200)
                .tint(distanciaColor)
                .padding(.horizontal)
            
            Text("O sensor de distância ajuda a detectar presença próxima da entrada da casa.")
                .font(.footnote)
                .foregroundColor(AppColors.textoSecundario)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
        }
        .padding()
        .background(AppColors.fundoClaro)
        .navigationTitle("Distância")
    }
}

struct RFIDView: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    @StateObject private var manager = MoradoresManager()
    
    @State private var nomeNovoMorador = ""
    @State private var codigoRFID = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 14) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 75))
                            .foregroundColor(viewModel.data.rfidAutorizado ? AppColors.verdeSeguro : AppColors.amareloAtencao)
                        
                        Text("Acesso RFID")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.textoPrincipal)
                        
                        Text(viewModel.data.rfidAutorizado ? "Acesso autorizado" : "Aguardando identificação")
                            .font(.headline)
                            .foregroundColor(viewModel.data.rfidAutorizado ? AppColors.verdeSeguro : AppColors.amareloAtencao)
                        
                        Text("Usuário: \(viewModel.data.usuario)")
                            .foregroundColor(AppColors.textoSecundario)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(AppColors.branco)
                    .cornerRadius(24)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cadastrar morador")
                            .font(.headline)
                            .foregroundColor(AppColors.textoPrincipal)
                        
                        Text("1. Digite o nome do morador")
                            .font(.caption)
                            .foregroundColor(AppColors.textoSecundario)
                        
                        TextField("Nome do morador", text: $nomeNovoMorador)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("2. Informe ou aproxime a tag RFID")
                            .font(.caption)
                            .foregroundColor(AppColors.textoSecundario)
                        
                        TextField("Código RFID", text: $codigoRFID)
                            .textFieldStyle(.roundedBorder)
                        
                        Button {

                            if !nomeNovoMorador.isEmpty &&
                               !codigoRFID.isEmpty {

                                manager.adicionar(
                                    nome: nomeNovoMorador,
                                    uid: codigoRFID
                                )

                                nomeNovoMorador = ""
                                codigoRFID = ""
                            }
                        } label: {
                            Text("Salvar morador")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColors.azulMarca)
                                .foregroundColor(AppColors.branco)
                                .cornerRadius(14)
                        }
                    }
                    .padding()
                    .background(AppColors.branco)
                    .cornerRadius(20)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Moradores cadastrados")
                            .font(.headline)
                            .foregroundColor(AppColors.textoPrincipal)
                        
                        ForEach(manager.moradores) { morador in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(AppColors.azulMarca)
                                
                                Text("\(morador.nome) - \(morador.uid)")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.textoPrincipal)
                                
                                Spacer()
                            }
                            .padding()
                            .background(AppColors.cardClaro)
                            .cornerRadius(12)
                        }                    }
                    .padding()
                    .background(AppColors.branco)
                    .cornerRadius(20)
                }
                .padding()
            }
            .background(AppColors.fundoClaro)
            .navigationTitle("RFID")
        }
    }
}

struct HistoricoView: View {
    @EnvironmentObject var viewModel: HackaGuardViewModel
    @State private var filtroSelecionado = "Todos"
    
    let filtros = ["Todos"]
    
    var eventosFiltrados: [EventoHistorico] {
        if filtroSelecionado == "Todos" {
            return viewModel.historico
        } else {
            return viewModel.historico.filter { $0.tipo == filtroSelecionado }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(filtros, id: \.self) { filtro in
                            Button {
                                filtroSelecionado = filtro
                            } label: {
                                Text(filtro)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(filtroSelecionado == filtro ? AppColors.azulMarca : AppColors.cardClaro)
                                    .foregroundColor(filtroSelecionado == filtro ? AppColors.branco : AppColors.textoPrincipal)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                
                List {
                    ForEach(eventosFiltrados) { evento in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: evento.icone)
                                .foregroundColor(evento.cor)
                                .frame(width: 32, height: 32)
                                .background(evento.cor.opacity(0.13))
                                .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(evento.titulo)
                                        .font(.headline)
                                        .foregroundColor(AppColors.textoPrincipal)
                                    
                                    Spacer()
                                    
                                    Text(evento.horario)
                                        .font(.caption)
                                        .foregroundColor(AppColors.textoSecundario)
                                }
                                
                                Text(evento.descricao)
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.textoSecundario)
                                
                                Text(evento.tipo)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(evento.cor)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.fundoClaro)
            }
            .background(AppColors.fundoClaro)
            .navigationTitle("Histórico")
        }
    }
}


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
                if case .string(let texto) = message {
                    self.processarMensagem(texto)
                }
                self.receber()
                
            case .failure(let erro):
                print("Erro Som/Movimento:", erro)
                self.webSocketTask = nil
            }
        }
    }
    
    private func processarMensagem(_ texto: String) {
        let mensagem = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        print("ESP2:", mensagem)
        
        if mensagem.hasPrefix("SOM:") {
            let valor = mensagem.replacingOccurrences(of: "SOM:", with: "")
            DispatchQueue.main.async {
                self.valorSom = Int(valor) ?? 0
            }
        }
        
        if mensagem.hasPrefix("HC:") {
            let valor = mensagem.replacingOccurrences(of: "HC:", with: "")
            DispatchQueue.main.async {
                self.distancia = Double(valor) ?? 0.0
            }
        }
    }
}

#Preview {
    ContentFrontView()
}
