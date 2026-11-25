import Foundation

/// Persist the last answer and passage completion together, before navigation.
/// Closing feedback or ending a session cannot turn an answered passage into an unseen one.
public enum ReadingAttemptJournal {
    public static func answer(reading: ReadingPassage, entryID: UUID, deviceID: UUID,
                              questionID: String, selection: Int, assisted: Bool,
                              events: [LearningEvent], now: Date = Date()) -> [LearningEvent] {
        guard !events.contains(where: { $0.id == entryID }),
              let question = reading.allQuestions.first(where: { $0.id == questionID }),
              question.choices.indices.contains(selection) else { return [] }
        let context = entryID.uuidString
        if events.contains(where: { $0.kind == .questionAttempt && $0.contextID == context && $0.targetID == questionID }) {
            return completion(reading: reading, entryID: entryID, deviceID: deviceID, events: events, now: now).map { [$0] } ?? []
        }
        let answer = LearningEvent(deviceID: deviceID, timestamp: now, kind: .questionAttempt,
            targetID: questionID, assisted: assisted, value: String(selection), contextID: context,
            correct: selection == question.answerIndex && !assisted)
        let completed = completion(reading: reading, entryID: entryID, deviceID: deviceID,
            events: events + [answer], now: now)
        return [answer] + (completed.map { [$0] } ?? [])
    }

    /// Also recovers legacy sessions whose last question was saved without a summary.
    public static func completion(reading: ReadingPassage, entryID: UUID, deviceID: UUID,
                                  events: [LearningEvent], now: Date = Date()) -> LearningEvent? {
        guard !events.contains(where: { $0.id == entryID }) else { return nil }
        let ids = Set(reading.allQuestions.map(\.id))
        let attempts = events.filter {
            $0.kind == .questionAttempt && $0.contextID == entryID.uuidString && ids.contains($0.targetID)
        }
        guard reading.allQuestions.allSatisfy({ question in attempts.contains { $0.targetID == question.id } }) else { return nil }
        let correct = reading.allQuestions.allSatisfy { question in
            let answers = attempts.filter { $0.targetID == question.id }
            return answers.allSatisfy { $0.correct == true && !$0.assisted && $0.value == String(question.answerIndex) }
        }
        return LearningEvent(id: entryID, deviceID: deviceID, timestamp: now, kind: .readingAttempt,
            targetID: reading.id, assisted: attempts.contains { $0.assisted }, value: correct ? "correct" : "incorrect")
    }
}
