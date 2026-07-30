import Foundation

/// The initials shown in Settings' identity header.
///
/// Lives here rather than beside the view because the interesting part is not
/// the circle, it is deciding what to put in it: the app's only name comes from
/// Kubera's profile, which may be a full name, a single word, an email address,
/// or absent. Each of those has to produce something, because a monogram that
/// renders empty reads as a broken avatar rather than as missing data.
enum Monogram {
    /// Two letters when there is more than one word, one when there is not.
    ///
    /// Takes the first *letter* of the first and last words rather than their
    /// first characters: a name written "(Sam) Rivera" or "@sam rivera" would
    /// otherwise contribute punctuation, and dropping the non-letter afterwards
    /// silently loses that word's initial entirely.
    static func initials(name: String?, email: String?) -> String {
        let words = (name ?? "").split(whereSeparator: \.isWhitespace)
        let ends = [words.first, words.count > 1 ? words.last : nil].compactMap(\.self)
        let letters = ends.compactMap { $0.first(where: \.isLetter) }

        if !letters.isEmpty { return String(letters).localizedUppercase }
        // A name of only punctuation or digits falls through to the email.
        if let letter = email?.first(where: \.isLetter) {
            return String(letter).localizedUppercase
        }
        return "K"
    }

    /// The name beside the monogram. The email is a better identifier than a
    /// generic label, so it is preferred over the fallback but not over a name.
    static func displayName(name: String?, email: String?) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }
        return "Kubera account"
    }
}
