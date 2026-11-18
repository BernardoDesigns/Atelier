# Fixture: spec interview, notification preferences

An invented session. Q is the skill, A is the user.

Q: What does this make possible, and for whom?
A: Account owners can pick which emails they get, from one page.
Q: So: owners choose which emails they receive, from the settings page. Right?
A: Yes.

Q: What's the tension?
A: They want fewer emails but are scared of missing a billing notice.
Q: I'll write it as: fewer emails against the fear of missing a billing notice. Billing wins if they conflict?
A: Yes, billing notices can't be turned off.

Q: What can I check, yes or no, when it's done?
A: Toggling a category saves. Billing is on and locked. A failed save says so and keeps the old value.
Q: Three lines then: a toggle saves, billing is locked on, a failed save shows an error and keeps the old value. Anything else?
A: No.

Q: Which states apply? Standard set is default, hover, focus, disabled, loading, empty, error.
A: Drop empty, it always has categories. Add "saving".
Q: So: default, hover, focus, disabled, loading, saving, error. Good?
A: Good.

Q: Is there a baseline?
A: No, first build.

Q: Out of scope?
A: Email delivery settings. And don't touch the four protected paths.

Q: Any gate exceptions?
A: None.

Q: Open questions?
A: Should digest emails default to on? Owner is product.
