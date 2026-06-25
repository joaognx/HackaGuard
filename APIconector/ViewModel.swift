//
//  ViewModel.swift
//  harryPotterAPI
//
//  Created by Turma02-18 on 03/06/26.
//
import Foundation
import Combine

class ViewModel: ObservableObject {
    @Published var Historico: [Historico] = []
    
    private let service = Service()
    private var cancellables = Set<AnyCancellable>()
    
    func fetch() {
        guard let url = URL(string: "http://127.0.0.1:1880/getCasa") else {
            return
        }
        service.fetchHistorico (url: url)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }) { Ocorrencia in
                self.Historico = Ocorrencia
            }

            .store(in: &cancellables)
    }
    func post(Ocorrencia: Historico) {
        guard let urlpost = URL(string: "http://127.0.0.1:1880/postCasa") else {
            return
        }
        
        service.postOcorrencia(url: urlpost, Ocorrencia: Ocorrencia)  { sucesso in
            DispatchQueue.main.async {
                if sucesso {
                    print("Música enviada como JSON único")
                    self.fetch()
                } else {
                    print("Erro ao enviar música")
                }
            }
        }
    }
}


