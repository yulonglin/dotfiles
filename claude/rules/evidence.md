# Evidence

**Anything attached to or submitted with an official or third-party request — government, employer, visa, insurance claim, audit — is in the form the source system produced**: a PDF or image printout, download or screenshot from that system (Gmail print-to-PDF, a portal download, the DocuSign or HelloSign PDF, a bank-app screenshot). Never a `.txt`, `.md` or self-rendered transcription: a text file can be written by anyone, so it proves nothing and reads as fabricated, however faithful it is.

Text captures of message bodies are working records. They live under `raw/` or `work/`, labelled as notes, and never appear in an attachment list or a submission folder.

When the connector cannot produce the printout (Gmail has no print call; a portal needs a login), the pack lists the source link — `https://mail.google.com/mail/u/0/#all/<threadId>`, the portal URL — next to a "print to PDF" step for the user, rather than substituting a text file. A gap the user can close in a minute beats a substitute that gets the whole pack questioned.

The inventory names the file format of every attachment, so a text file in the list is visible at a glance and a missing printout is a listed gap, not a silent one.

Mechanics — headless Chrome print, RAW-MIME attachment recovery — are in the `gmail-connector` skill; this file only says what counts.
