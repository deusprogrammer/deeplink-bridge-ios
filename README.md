# Deeplink Bridge

An iOS utility for launching USAA deep links manually or running a sequence of deep-link tests from a test server.

## Requirements

- The USAA app must already be installed and logged in. Deep links may not work if the user is not logged in.
- The first time you begin a test, iOS will ask permission to open the USAA app. Allow it so the bridge can launch the test deep links.

## Use

Use **Launch USAA** to open a manually entered path. For a test run, enter the test server's base URL and tap **Begin Test**. The server URL is saved between app launches.

The bridge requests `GET /next` for a URI, then sends that URI to `POST /continue` before opening the corresponding deep link in USAA. When the app returns to the foreground, it requests the next URI. An HTTP `410` from `/next` makes the bridge call `/quit` and stop the test. Use **Stop Test** to end a run manually.

The diagnostic section shows the public IP address, request URLs, HTTP methods and response statuses.