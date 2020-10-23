import Foundation

extension SuggestionType {
    var trigger: String {
        switch self {
        case .mentions: return "@"
        case .xposts: return "+"
        }
    }
}

@objc public extension SuggestionsTableView {

    func suggestions(for siteID: NSNumber, completion: @escaping ([UserSuggestion]?) -> Void) {
        guard let blog = SuggestionService.shared.persistedBlog(for: siteID) else { return }
        SuggestionService.shared.suggestions(for: blog, completion: completion)
    }

    var suggestionTrigger: String { return suggestionType.trigger }

    func siteSuggestions(for siteID: NSNumber, completion: @escaping ([SiteSuggestion]?) -> Void) {
        let context = ContextManager.shared.mainContext
        guard let blog = BlogService(managedObjectContext: context).blog(byBlogId: siteID) else { return }

        XpostSuggestionService.suggestions(for: blog) { result in
            switch result {
            case .success(let siteSuggestions):
                completion(siteSuggestions)
            case .failure:
                completion(nil)
            }
        }
    }

    func predicate(for searchQuery: String) -> NSPredicate {
        switch suggestionType {
        case .mentions:
            return NSPredicate(format: "(displayName contains[c] %@) OR (username contains[c] %@)", searchQuery, searchQuery)
        case .xposts:
            return NSPredicate(format: "(title contains[c] %@) OR (siteURL.absoluteString contains[c] %@)", searchQuery, searchQuery)
        }
    }

    func title(for suggestion: AnyObject) -> String? {
        let title: String?
        switch (suggestionType, suggestion) {
        case (.mentions, let suggestion as UserSuggestion):
            title = suggestion.username
        case (.xposts, let suggestion as SiteSuggestion):
            title = suggestion.subdomain
        default:
            return nil
        }
        return title.map { suggestionType.trigger.appending($0) }
    }

    func subtitle(for suggestion: AnyObject) -> String? {
        switch (suggestionType, suggestion) {
        case (.mentions, let suggestion as UserSuggestion):
            return suggestion.displayName
        case (.xposts, let suggestion as SiteSuggestion):
            return suggestion.title
        default:
            return nil
        }
    }

    private func imageURLForSuggestion(at indexPath: IndexPath) -> URL? {
        let suggestion = searchResults[indexPath.row]
        switch (suggestionType, suggestion) {
        case (.mentions, let suggestion as UserSuggestion):
            return suggestion.imageURL
        case (.xposts, let suggestion as SiteSuggestion):
            return suggestion.blavatarURL
        default:
            return nil
        }
    }

    func loadImage(for suggestion: AnyObject, in cell: SuggestionsTableViewCell, at indexPath: IndexPath) {

        cell.iconImageView.image = UIImage(named: "gravatar")

        guard let imageURL = imageURLForSuggestion(at: indexPath) else { return }
        cell.imageDownloadHash = imageURL.hashValue

        retrieveIcon(for: imageURL) { image in
            guard indexPath.row < self.searchResults.count else { return }
            if let reloadedImageURL = self.imageURLForSuggestion(at: indexPath), reloadedImageURL.hashValue == cell.imageDownloadHash {
                cell.iconImageView.image = image
            }
        }
    }

    private func suggestionText(for suggestion: Any) -> String? {
        switch (suggestionType, suggestion) {
        case (.mentions, let suggestion as UserSuggestion):
            return suggestion.username
        case (.xposts, let suggestion as SiteSuggestion):
            return suggestion.title
        default: return nil
        }
    }

    func fetchSuggestions(for siteID: NSNumber) {
        switch suggestionType {
        case .mentions:
            suggestions(for: siteID) { userSuggestions in
                self.suggestions = userSuggestions
                self.showSuggestions(forWord: self.searchText)
            }
        case .xposts:
            siteSuggestions(for: siteID) { siteSuggestions in
                self.suggestions = siteSuggestions
                self.showSuggestions(forWord: self.searchText)
            }
        default: return;
        }
    }

    private func retrieveIcon(for imageURL: URL?, success: @escaping (UIImage?) -> Void) {
        let imageSize = CGSize(width: SuggestionsTableViewCellIconSize, height: SuggestionsTableViewCellIconSize)
        if let image = cachedIcon(for: imageURL, with: imageSize) {
            success(image)
        } else {
            fetchIcon(for: imageURL, with: imageSize, success: success)
        }
    }

    private func cachedIcon(for imageURL: URL?, with size: CGSize) -> UIImage? {
        var hash: NSString?
        let type = avatarSourceType(for: imageURL, with: &hash)

        if let hash = hash, let type = type {
            return WPAvatarSource.shared()?.cachedImage(forAvatarHash: hash as String, of: type, with: size)
        }
        return nil
    }

    private func fetchIcon(for imageURL: URL?, with size: CGSize, success: @escaping ((UIImage?) -> Void)) {
        var hash: NSString?
        let type = avatarSourceType(for: imageURL, with: &hash)

        if let hash = hash, let type = type {
            WPAvatarSource.shared()?.fetchImage(forAvatarHash: hash as String, of: type, with: size, success: success)
        } else {
            success(nil)
        }
    }
}

extension SuggestionsTableView {
    func avatarSourceType(for imageURL: URL?, with hash: inout NSString?) -> WPAvatarSourceType? {
        if let imageURL = imageURL {
            return WPAvatarSource.shared()?.parseURL(imageURL, forAvatarHash: &hash)
        }
        return .unknown
    }
}

extension SuggestionsTableView: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let suggestion = searchResults[indexPath.row]
        let text = suggestionText(for: suggestion)
        let currentSearchText = String(searchText.dropFirst())
        suggestionsDelegate?.suggestionsTableView?(self, didSelectSuggestion: text, forSearchText: currentSearchText)
    }
}
