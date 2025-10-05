//
//  VLMService.swift
//  EchoSight
//
//  Communicates with OpenRouter's VLM API to provide scene Q&A and obstacle advice.
//

import Foundation
import UIKit

class VLMService {
    
    static let shared = VLMService()
    
    private var apiKey: String {
        return Config.openRouterAPIKey ?? ""
    }
    private let baseURL = "https://openrouter.ai/api/v1"
    private let model = "google/gemini-2.5-flash-lite-preview-09-2025"
    
    private init() {}
    
    /// Compress and encode image to Base64
    private func compressAndEncodeImage(_ image: UIImage, maxSizeMB: Double = 15.0) -> String? {
        guard var imageData = image.jpegData(compressionQuality: 0.85) else {
            return nil
        }
        
        // If image is too large, reduce quality
        let qualities: [CGFloat] = [0.85, 0.70, 0.50, 0.30]
        for quality in qualities {
            if let compressedData = image.jpegData(compressionQuality: quality) {
                let estimatedBase64Size = Double(compressedData.count) * 4.0 / 3.0
                if estimatedBase64Size < maxSizeMB * 1024 * 1024 {
                    imageData = compressedData
                    break
                }
            }
        }
        
        // If still too large, downscale
        if Double(imageData.count) * 4.0 / 3.0 > maxSizeMB * 1024 * 1024 {
            let maxDimension: CGFloat = 512
            let size = image.size
            let ratio = maxDimension / max(size.width, size.height)
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let resized = resizedImage, let data = resized.jpegData(compressionQuality: 0.5) {
                imageData = data
            }
        }
        
        return imageData.base64EncodedString()
    }
    
    /// Get obstacle avoidance advice when warning triggers
    func getObstacleAvoidanceAdvice(image: UIImage, detectedObject: String, distance: Float, completion: @escaping (Result<String, Error>) -> Void) {
        
        guard let base64Image = compressAndEncodeImage(image) else {
            completion(.failure(NSError(domain: "VLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])))
            return
        }
        
        let prompt = """
        You are a blind navigation assistant. A \(detectedObject) is \(String(format: "%.1f", distance))m ahead. 
        Give ONE brief avoidance instruction in 10 words maximum.
        """
        
        sendVLMRequest(prompt: prompt, base64Image: base64Image, completion: completion)
    }
    
    /// Handle natural language query with image context
    func handleNaturalLanguageQuery(query: String, image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        
        guard let base64Image = compressAndEncodeImage(image) else {
            completion(.failure(NSError(domain: "VLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])))
            return
        }
        
        let prompt = """
        You are a helpful assistant for a blind person. Question: "\(query)"
        Answer briefly in 10 words maximum based on the image.
        """
        
        sendVLMRequest(prompt: prompt, base64Image: base64Image, completion: completion)
    }
    
    /// Describe the environment in the image for voice interaction mode
    func describeEnvironment(image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        
        guard let base64Image = compressAndEncodeImage(image) else {
            completion(.failure(NSError(domain: "VLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])))
            return
        }
        
        let prompt = """
        You are a helpful assistant for a blind person. Describe the environment in this image briefly.
        Focus on key objects, layout, and important details. Keep it under 20 words.
        """
        
        sendVLMRequest(prompt: prompt, base64Image: base64Image, completion: completion)
    }
    
    /// Send a VLM request to OpenRouter API
    private func sendVLMRequest(prompt: String, base64Image: String, completion: @escaping (Result<String, Error>) -> Void) {
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            completion(.failure(NSError(domain: "VLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if apiKey.isEmpty {
            completion(.failure(NSError(domain: "VLMService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing OPENROUTER_API_KEY"])))
            return
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "VLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else {
                    completion(.failure(NSError(domain: "VLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                }
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
}

