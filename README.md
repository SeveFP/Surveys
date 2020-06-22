### Surveys

Surveys is a [Riddim](http://code.matthewwild.co.uk/riddim) plugin for handling surveys within a MUC.
Users can create surveys with or without expiration date, surveys with a specific set of possible
answers as well as surveys with open questions allowing any kind of response (e.g. gathering feedback)
Multiple surveys can be ongoing at the same time.

Current implementation is based on commands like `add` or `list` written in the message body (`!survey add ...`).
Implementing [XEP-0004 Data Forms](https://xmpp.org/extensions/xep-0004.html) for clients that support it, would enhance quite a bit the experience.
