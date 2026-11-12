// Gemini API client (streaming, with model fallback).

import Foundation

enum Gemini {
    struct Failure: Error { let message: String }

    /// Sends one tiny request to find out whether a key works. It costs a fraction of a cent at most.
    static func checkKey(_ rawKey: String) async -> KeyCheckResult {
        let key = KeyCheck.cleaned(rawKey)
        guard !key.isEmpty else { return KeyCheck.result(status: 0, hasKey: false) }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(configuredModel()):generateContent") else {
            return KeyCheck.result(status: 404)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 15
        let body: [String: Any] = ["contents": [["role": "user", "parts": [["text": "Reply with the word OK."]]]]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return KeyCheck.result(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return KeyCheck.result(status: 0)
        }
    }

    /// Streams the answer. `onText` is called for every piece of text.
    static func ask(imageBase64: String, question: String, mode: AppMode,
                    onModel: @escaping @Sendable (String) -> Void,
                    onText: @escaping @Sendable (String) -> Void) async throws {
        guard let key = KeyStore.load() else {
            throw Failure(message: "No API key. Open Settings… from the ScreenPulse menu bar icon and add your Gemini API key.")
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": Prompts.system(for: mode) + loadKnowledge()]]],
            "contents": [[
                "role": "user",
                "parts": [
                    ["inlineData": ["mimeType": "image/png", "data": imageBase64]],
                    ["text": question.isEmpty ? Prompts.defaultQuestion(for: mode) : question],
                ],
            ]],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        // Focus Mode: low thinking makes the short answer faster without losing accuracy in the
        // benchmark. Normal Mode uses the model's default thinking for better explanations.
        var lowThinkingBody = body
        lowThinkingBody["generationConfig"] = ["thinkingConfig": ["thinkingLevel": "low"]]
        let lowThinkingPayload = try JSONSerialization.data(withJSONObject: lowThinkingBody)

        var lastError = "Unknown error"
        var seen = Set<String>()
        // One attempt per model: if it is overloaded or too slow we move straight on to the next.
        for model in [configuredModel()] + fallbackModels where seen.insert(model).inserted {
            onModel(model)
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse") else {
                lastError = "Invalid model name: \(model)"
                continue
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = (mode == .focus && model.hasPrefix("gemini-3")) ? lowThinkingPayload : payload
            req.timeoutInterval = mode == .focus ? 15 : 30

            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await URLSession.shared.bytes(for: req)
            } catch {
                // Timeout or network error: try the next model instead of giving up.
                lastError = "No response from \(model): \(error.localizedDescription)"
                continue
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                var wrote = false
                var finish = ""
                for try await line in bytes.lines where line.hasPrefix("data:") {
                    let json = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    guard let d = json.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let cand = (obj["candidates"] as? [[String: Any]])?.first else { continue }
                    let parts = ((cand["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                    for p in parts where (p["thought"] as? Bool) != true {
                        if let t = p["text"] as? String { onText(t); wrote = true }
                    }
                    if let f = cand["finishReason"] as? String { finish = f }
                }
                if !wrote { onText("No answer received.") }
                if finish == "MAX_TOKENS" { onText("\n\n[The answer was cut short.]") }
                if finish == "SAFETY" { onText("\n\n[Gemini declined to answer this request.]") }
                return
            }

            var errBody = ""
            for try await line in bytes.lines { errBody += line + "\n" }
            if let d = errBody.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let m = (o["error"] as? [String: Any])?["message"] as? String { errBody = m }
            lastError = "Gemini error (\(status)): \(errBody.trimmingCharacters(in: .whitespacesAndNewlines))"

            switch status {
            case 402: // applies to every model, so there is no point in trying the rest
                throw Failure(message: "Your Gemini credits are used up.\n\nTop up under Billing at aistudio.google.com/projects and try again.")
            case 400, 401, 403:
                throw Failure(message: lastError) // wrong key or similar: retrying will not help
            case 429:
                lastError = "The request limit has been reached (429).\n\nWait a minute, or check your quota at aistudio.google.com."
            default:
                break // 404, 500, 503 etc.: next model
            }
        }
        throw Failure(message: lastError)
    }
}
