import Foundation

/// The rotating greeting at the top of the Overview, in the spirit of Kubera's
/// web dashboard: "Hej, Kenneth" one visit, "Ahlan, Kenneth" the next.
///
/// Two kinds are mixed: time-of-day greetings in English, and hellos from other
/// languages. Each carries a translation note so the app can explain an
/// unfamiliar one rather than leaving the reader guessing — the web app does
/// this with a footnote marker.
enum Greeting {
    struct Phrase: Equatable {
        /// The greeting itself, without the name: "Good afternoon", "Ahlan".
        let text: String
        /// Nil for plain English, otherwise "That's 'Hello' in Arabic".
        let note: String?
    }

    /// Hellos from other languages. Kept short enough to sit beside a name on
    /// one line at large text sizes.
    static let hellos: [Phrase] = [
        Phrase(text: "Hej", note: "That's “Hello” in Danish"),
        Phrase(text: "Ahlan", note: "That's “Hello” in Arabic"),
        Phrase(text: "Hola", note: "That's “Hello” in Spanish"),
        Phrase(text: "Bonjour", note: "That's “Hello” in French"),
        Phrase(text: "Ciao", note: "That's “Hello” in Italian"),
        Phrase(text: "Hallo", note: "That's “Hello” in German"),
        Phrase(text: "Olá", note: "That's “Hello” in Portuguese"),
        Phrase(text: "Namaste", note: "That's “Hello” in Hindi"),
        Phrase(text: "Konnichiwa", note: "That's “Hello” in Japanese"),
        Phrase(text: "Nǐ hǎo", note: "That's “Hello” in Mandarin"),
        Phrase(text: "Annyeong", note: "That's “Hello” in Korean"),
        Phrase(text: "Shalom", note: "That's “Hello” in Hebrew"),
        Phrase(text: "Privet", note: "That's “Hello” in Russian"),
        Phrase(text: "Merhaba", note: "That's “Hello” in Turkish"),
        Phrase(text: "Jambo", note: "That's “Hello” in Swahili"),
        Phrase(text: "Sawubona", note: "That's “Hello” in Zulu"),
        Phrase(text: "Góðan dag", note: "That's “Good day” in Icelandic"),
        Phrase(text: "Hei", note: "That's “Hello” in Finnish"),
    ]

    /// English time-of-day greetings, so the rotation sometimes reads as plain
    /// context rather than a language lesson.
    static func timeOfDay(for date: Date, calendar: Calendar) -> Phrase {
        switch calendar.component(.hour, from: date) {
        case 0 ..< 5: return Phrase(text: "Still up", note: nil)
        case 5 ..< 12: return Phrase(text: "Good morning", note: nil)
        case 12 ..< 18: return Phrase(text: "Good afternoon", note: nil)
        default: return Phrase(text: "Good evening", note: nil)
        }
    }

    /// Picks a greeting deterministically from the day and hour, so it changes
    /// as the day goes on but never flickers between two renders of the same
    /// screen. Roughly one visit in three gets the English time-of-day form.
    static func phrase(for date: Date, calendar: Calendar = .current) -> Phrase {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let hour = calendar.component(.hour, from: date)
        // Coprime multipliers, deliberately not 24: a factor sharing 3 with the
        // branch below aliases, and `day * 24 + hour` made the choice depend on
        // the hour alone — every 9am was "Good morning", forever.
        let seed = day * 13 + hour * 5

        if seed % 3 == 0 {
            return timeOfDay(for: date, calendar: calendar)
        }
        return hellos[seed % hellos.count]
    }

    /// "Hej, Kenneth" / "Good afternoon, Kenneth", or just the greeting when no
    /// name is known — never a dangling comma.
    static func line(for date: Date, name: String?, calendar: Calendar = .current) -> String {
        let phrase = phrase(for: date, calendar: calendar)
        guard let name = firstName(from: name) else { return phrase.text }
        return "\(phrase.text), \(name)"
    }

    /// Portfolio names are the only name the app has, and they are often a
    /// person's ("Kenneth") but sometimes not ("Main portfolio"). Take the first
    /// word, and treat the generic ones as nameless.
    static func firstName(from name: String?) -> String? {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let generic = ["main", "portfolio", "personal", "default", "my"]
        guard let first = raw.split(separator: " ").first.map(String.init),
              !generic.contains(first.lowercased()) else {
            return nil
        }
        return first
    }
}
