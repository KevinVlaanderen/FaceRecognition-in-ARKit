//
//  PatientInfo.swift
//  faceIT
//
//  Created by Gareth Steyn on 10/01/2018.
//  Copyright © 2018 NovaTec GmbH. All rights reserved.
//

import Foundation

class Patient {
    let name: String
    let heartBeat: String
    
    init(name: String, heartBeat: String) {
        self.name = name
        self.heartBeat = heartBeat
    }
}
