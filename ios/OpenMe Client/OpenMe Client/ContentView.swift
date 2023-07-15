//
//  ContentView.swift
//  OpenMe Client
//
//  Created by Merlos on 7/15/23.
//

import SwiftUI
import Security

struct ContentView: View {
    @State private var serverAddress = "localhost"
    @State private var port = "5414"
    @State private var ipAddress = ""
    let defaultServerAddress = "localhost"
    let defaultPort = "5414"
    
    let certificateName = "client_certificate"
    let certificateExtension = "p12"
    let certificatePassword = "password"

    var body: some View {
        VStack {
            TextField("Server Address", text: $serverAddress)
                .padding()
            
            TextField("Port", text: $port)
                .keyboardType(.numberPad)
                .padding()
            
            TextField("IP Address (optional)", text: $ipAddress)
                .padding()
            
            Button(action: {
                if serverAddress.isEmpty || port.isEmpty {
                    // Display error message
                    print("Please fill in all required fields.")
                } else {
                    // Send TCP request
                    let request = ipAddress.isEmpty ? "OPEN ME" : "OPEN \(ipAddress)"
                    sendTCPRequest(request: request)
                }
            }) {
                Text("Send Request")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding()
        }
    }
    
    func sendTCPRequest(request: String) {
        var inputStream: InputStream?
        var outputStream: OutputStream?
        
        Stream.getStreamsToHost(withName: serverAddress, port: Int(port)!, inputStream: &inputStream, outputStream: &outputStream)
        
        guard let input = inputStream, let output = outputStream else {
            print("Failed to create input/output streams.")
            return
        }
        
        let clientCertURL = Bundle.main.url(forResource: certificateName, withExtension: certificateExtension)!
        let clientCertData = try! Data(contentsOf: clientCertURL)
        
        let sslSettings: [NSString: Any] = [
            kCFStreamSSLLevel as NSString: kCFStreamSocketSecurityLevelNegotiatedSSL,
            kCFStreamSSLCertificates as NSString: [clientCertData] as CFArray,
            kCFStreamSSLValidatesCertificateChain as NSString: kCFBooleanTrue
        ]
        
        input.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        output.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        
        CFReadStreamSetProperty(input, CFStreamPropertyKey(kCFStreamPropertySSLSettings), sslSettings as CFDictionary)
        CFWriteStreamSetProperty(output, CFStreamPropertyKey(kCFStreamPropertySSLSettings), sslSettings as CFDictionary)
        
        input.open()
        output.open()
        
        let requestData = request.data(using: .utf8)!
        _ = requestData.withUnsafeBytes {
            output.write($0, maxLength: requestData.count)
        }
        
        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = input.read(&buffer, maxLength: buffer.count)
        if bytesRead > 0, let response = String(bytes: buffer, encoding: .utf8) {
            print("Received response: \(response)")
        }
        
        input.close()
        output.close()
    }
}

/*
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Hello, world!")
        }
        .padding()
    }
}
 */

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
