//
//  MoradoresManager.swift
//  HackaGuard
//
//  Created by Turma02-18 on 23/06/26.
//

import Foundation
import Combine

struct Morador: Codable, Identifiable {
    let id = UUID()
    var nome: String
    var uid: String
}

class MoradoresManager: ObservableObject {

    @Published var moradores: [Morador] = []

    private let chave = "moradores_rfid"

    init() {
        carregar()

        if moradores.isEmpty {
            adicionar(
                nome: "João Gabriel",
                uid: "F3 1C 40 14" // sua tag
            )
        }
    }

    func adicionar(nome: String, uid: String) {

        let novo = Morador(
            nome: nome,
            uid: uid.uppercased()
        )

        moradores.append(novo)

        salvar()
    }

    func salvar() {

        if let dados = try? JSONEncoder().encode(moradores) {
            UserDefaults.standard.set(dados, forKey: chave)
        }
    }

    func carregar() {

        guard let dados = UserDefaults.standard.data(forKey: chave),
              let lista = try? JSONDecoder().decode([Morador].self, from: dados)
        else {
            return
        }

        moradores = lista
    }

    func buscar(uid: String) -> Morador? {

        moradores.first {
            $0.uid.uppercased() == uid.uppercased()
        }
    }
}
