import Foundation

/// A service to fetch and persist a list of sites that can be used for x-posting.
struct XpostSuggestionService {

    enum ServiceError: Error {
        case missingAPI
        case missingManagedObjectContext
        case hostnameNotAvailable
        case noResultsAvailable
    }

    static var hasRequested = false

    /**
    Fetch cached suggestions if available, otherwise from the network if the device is online.

    @param the blog/site to retrieve suggestions for
    @param completion callback containing list of suggestions, or nil if unavailable
    */
    static func suggestions(for blog: Blog, completion: @escaping (Result<[SiteSuggestion], Error>) -> Void) {

        if let results = retrievePersistedResults(for: blog), results.isEmpty == false {
            completion(.success(results))
        } else if ReachabilityUtils.isInternetReachable() {
            fetchAndPersistSuggestions(for: blog, completion: completion)
        } else {
            completion(.failure(ServiceError.noResultsAvailable))
        }
    }

    private static func fetchAndPersistSuggestions(for blog: Blog, completion: @escaping (Result<[SiteSuggestion], Error>) -> Void) {

        guard !hasRequested else { return }
        self.hasRequested = true

        guard let api = blog.wordPressComRestApi() else {
            completion(.failure(ServiceError.missingAPI))
            return
        }

        guard let managedObjectContext = blog.managedObjectContext else {
            completion(.failure(ServiceError.missingManagedObjectContext))
            return
        }

        guard let hostname = blog.hostname else {
            completion(.failure(ServiceError.hostnameNotAvailable))
            return
        }

        let urlString = "/wpcom/v2/sites/\(hostname)/xposts"

        api.GET(urlString, parameters: nil) { responseObject, httpResponse in
            do {
                let data = try JSONSerialization.data(withJSONObject: responseObject)

                try self.purgeExistingResults(for: blog, using: managedObjectContext)

                let siteSuggestions = try self.persist(data: data, to: blog, using: managedObjectContext)
                completion(.success(siteSuggestions))
            } catch {
                completion(.failure(error))
            }

            self.hasRequested = false
        } failure: { error, _ in
            completion(.failure(error))
            self.hasRequested = false
        }
    }

    private static func purgeExistingResults(for blog: Blog, using managedObjectContext: NSManagedObjectContext) throws {
        blog.siteSuggestions?.forEach { siteSuggestion in
            managedObjectContext.delete(siteSuggestion)
        }
        try managedObjectContext.save()
    }

    private static func persist(data: Data, to blog: Blog, using managedObjectContext: NSManagedObjectContext) throws -> [SiteSuggestion] {
        let decoder = JSONDecoder()
        decoder.userInfo[CodingUserInfoKey.managedObjectContext] = managedObjectContext
        let siteSuggestions = try decoder.decode([SiteSuggestion].self, from: data)
        blog.siteSuggestions = Set(siteSuggestions)
        try managedObjectContext.save()
        return siteSuggestions
    }

    private static func retrievePersistedResults(for blog: Blog) -> [SiteSuggestion]? {
        guard let results = blog.siteSuggestions else { return nil }
        return Array(results)
    }
}

extension XpostSuggestionService.ServiceError: CustomNSError {
    static var errorDomain: String { return "XpostSuggestionService.ServiceError" }

    var errorCode: Int { return 0 }

    var errorUserInfo: [String : Any] {
        switch self {
        case .missingAPI: return [NSDebugDescriptionErrorKey: "Blog hostname not available"]
        case .missingManagedObjectContext: return [NSDebugDescriptionErrorKey: "Managed object context not available"]
        case .hostnameNotAvailable: return [NSDebugDescriptionErrorKey: "Blog hostname not available"]
        case .noResultsAvailable: return [NSDebugDescriptionErrorKey: "The device is offline and there are no suggestions in the cache"]
        }
    }
}
