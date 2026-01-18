# burn

A macOS SwiftUI app that builds cumulative burn charts for job codes using the
QuickBooks Time (formerly TSheets) API. It pulls month-by-month timesheets for
one job, projects remaining work through the Period of Performance (PoP), and
overlays configurable ceiling thresholds.

## Features

- Job tree browser (parent/child job codes)
- Cumulative burn chart with projections
- PoP date management per job
- Ceiling releases with 75% and 100% threshold lines
- Export chart image to Photos

## Requirements

- macOS (SwiftUI + Charts)
- Xcode (to build and run)
- QuickBooks Time (TSheets) API token

## Setup

1. Copy `burn/config.example.json` to `burn/config.json` and fill in your API info:

   ```json
   {
     "API_URL": "https://rest.tsheets.com/api/v1",
     "API_TOKEN": "YOUR_TOKEN_HERE"
   }
   ```

2. Add `config.json` to the Xcode project and ensure it is included under
   "Copy Bundle Resources" for the `burn` target.

3. Build and run from Xcode.

## Usage

1. Select a leaf job code on the left.
2. Click **Manage Ceiling** and set PoP Start/End.
3. Add ceiling releases as needed and click **Save**.
4. Choose a **Query Stop** date and click **Generate Burn Chart**.
5. Optional: **Save Chart to Photos** to export a PNG.

## Data storage

Ceiling releases and PoP dates are stored per job in Application Support under
`<bundle-id>/ceiling/job_<id>.json`.

## Notes

- `config.json` contains secrets. Do not commit it to public source control.
- This project is not affiliated with Intuit or QuickBooks Time.

