import Foundation

let urlStr = "https://music.akhilhub.uk/rest/stream.view?u=admin&t=TOKEN&s=SALT&v=1.16.1&c=submariner&id=SOME_ID&estimateContentLength=true"
// We don't have the real auth, but we can just see if it responds with 401 and look at the headers.
let url = URL(string: urlStr)!
var req = URLRequest(url: url)
req.httpMethod = "HEAD"
let group = DispatchGroup()
group.enter()
URLSession.shared.dataTask(with: req) { data, resp, err in
    if let http = resp as? HTTPURLResponse {
        print("Status: \(http.statusCode)")
        for (k, v) in http.allHeaderFields {
            print("\(k): \(v)")
        }
    }
    if let err = err {
        print("Error: \(err)")
    }
    group.leave()
}.resume()
group.wait()
