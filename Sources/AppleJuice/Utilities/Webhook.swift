import Foundation

/// Home Assistant webhook integration.
enum Webhook {
    /// Send a webhook event to Home Assistant.
    static func send(
        stage: String,
        battery: String? = nil,
        voltage: String? = nil,
        health: String? = nil
    ) {
        let config = ConfigStore()
        guard let webhookId = config.webhookId else { return }
        let haURL = config.haURL ?? "http://homeassistant.local:8123"

        var payload: [String: String] = ["stage": stage]
        if let battery { payload["battery"] = battery }
        if let voltage { payload["voltage"] = voltage }
        if let health { payload["health"] = health }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "\(haURL)/api/webhook/\(webhookId)")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error { log("Webhook error: \(error.localizedDescription)") }
            else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                log("Webhook HTTP \(http.statusCode)")
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 15)
    }
}
