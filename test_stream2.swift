import Foundation

let urlStr = "https://music.akhilhub.uk/rest/stream.view?u=admin&t=TOKEN&s=SALT&v=1.16.1&c=submariner&id=SOME_ID&estimateContentLength=true"
let url = URL(string: urlStr)!
var req = URLRequest(url: url)
req.httpMethod = "GET"
req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
let group = DispatchGroup()
group.enter()
URLSession.shared.dataTask(with: req) { data, resp, err in
    if let http = resp as? HTTPURLResponse {
        print("Status: \(http.statusCode)")
        for (k, v) in http.allHeaderFields {
            print("\(k): \(v)")
        }
    }
    group.leave()
}.resume()
group.wait()
