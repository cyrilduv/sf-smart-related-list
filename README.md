# Smart Related List — Lightning Web Component

A fully configurable, reusable related list component for Salesforce Lightning record pages. Drop it onto any record page via Lightning App Builder and configure it entirely through point-and-click properties — no code changes needed.

<img width="955" height="576" alt="Screenshot 2026-03-27 at 8 54 45 pm" src="https://github.com/user-attachments/assets/fd99d960-f38e-4b72-89f5-faa8f3ba93b5" />


---

## Features

| Feature | Description |
|---|---|
| **Dynamic Columns** | Specify any combination of fields to display as columns — works with any standard or custom object. |
| **Client-Side Search** | Optional search bar that filters rows instantly across all visible column values. |
| **Client-Side Sorting** | Click column headers to sort. Optionally restrict which columns are sortable. |
| **Pagination** | Automatic page controls with a "Showing X–Y of Z records" label. |
| **Inline Editing** | Edit cells directly in the table — supports text, number, date, and **picklist dropdowns**. Save all changes at once. |
| **Row Colour Coding** | Apply a coloured left border to rows based on a field value (e.g. Status = "Active" → green). |
| **CSV Export** | Export all loaded records (not just the current page) to a CSV file. |
| **New Record Button** | Create a child record pre-populated with the parent lookup. |
| **Row-Level Actions** | Add a primary action button per row (e.g. "Edit") that navigates to the record. |
| **Same-Tab Navigation** | Clicking a record name navigates in the same browser tab (no new tabs). |

---

## Setup Instructions

### 1. Deploy to your org

Deploy via the GitHub Actions workflow — it runs only the required test class (`SmartRelatedListControllerTest`) instead of all tests in the org.

#### One-time setup

1. Generate auth URLs for each target org:
   ```bash
   sf org display --target-org <prod-alias> --verbose
   sf org display --target-org <sandbox-alias> --verbose
   ```
2. Copy the **Sfdx Auth Url** from each command output.
3. In your GitHub repo, go to **Settings > Secrets and variables > Actions** and create:
   - `SFDX_AUTH_URL_PROD` — paste the production auth URL
   - `SFDX_AUTH_URL_SANDBOX` — paste the sandbox auth URL

#### Run the deployment

1. Go to the **Actions** tab in your GitHub repo.
2. Select **Deploy to Salesforce** from the workflow list.
3. Click **Run workflow**.
4. Choose the target environment (**production** or **sandbox**) and click **Run workflow**.

### 2. Assign the permission set

After deployment, assign the **Smart Related List User** permission set to users who need access:

1. Go to **Setup → Permission Sets**.
2. Click **Smart Related List User**.
3. Click **Manage Assignments → Add Assignment**.
4. Select the users and click **Assign**.

### 3. Add to a record page

1. Navigate to any record page (e.g. an Account record).
2. Click the gear icon and select **Edit Page** to open Lightning App Builder.
3. In the left panel, search for **"Smart Related List"**.
4. Drag the component onto the page layout.
5. Configure the properties in the right panel (see [App Builder Properties](#app-builder-properties) below).
6. Click **Save** and **Activate** the page.

### 4. Example: Contacts on an Account page

| Property | Value |
|---|---|
| Card Title | `Contacts` |
| Child Object API Name | `Contact` |
| Parent Lookup Field | `AccountId` |
| Fields to Display | `Name,FirstName,LastName,Email,Phone,Status__c` |
| Sortable Fields | `LastName,Email` |
| Row Limit | `10` |
| Enable Search | `true` |
| Enable Inline Edit | `true` |
| Enable CSV Export | `true` |
| Enable New Record | `true` |

---

## Row Colour Coding

Apply a coloured 4px left border to each row based on a field value.

### How it works

1. Set **Color Field** to the API name of a text or picklist field (e.g. `Status__c`).
2. Set **Color Rules (JSON)** to a JSON object mapping field values to colour tokens.

### Available colour tokens

| Token | Hex | Usage |
|---|---|---|
| `red` | `#e74c3c` | Critical / negative statuses |
| `orange` | `#e67e22` | Warning / attention statuses |
| `green` | `#27ae60` | Positive / active statuses |
| `blue` | `#2980b9` | Informational statuses |
| `grey` | `#95a5a6` | Default fallback for unmapped values |

### Example

**Color Field:** `Status__c`

**Color Rules:**
```json
{"Active":"green","Left Company":"red","On Leave":"orange"}
```

This will render:
- Contacts with `Status__c = "Active"` → green left border
- Contacts with `Status__c = "Left Company"` → red left border
- Contacts with `Status__c = "On Leave"` → orange left border
- Any other value → grey left border

---

## Inline Editing

When **Enable Inline Edit** is `true`:

- **Text, number, email, phone, date fields** — click a cell to edit inline as a text input.
- **Picklist fields** — click a cell to get a native dropdown with the actual picklist values from Salesforce.
- **Save All / Cancel** buttons appear in the toolbar when there are unsaved changes.
- Records are saved using Lightning Data Service (`updateRecord`), which respects validation rules, triggers, and field-level security.
- On success: a toast notification appears and the table refreshes.
- On failure: an error toast shows the failing field message.

---

## CSV Export

When **Enable CSV Export** is `true`:

- Clicking **Export CSV** exports **all loaded records** (not just the current page).
- The CSV includes all visible columns plus the Name field.
- The file opens in a new browser tab — save it from there.
- A UTF-8 BOM is prepended so Excel handles special characters correctly.

---

## Security

| Layer | Enforcement |
|---|---|
| **Sharing rules** | The Apex controller uses `with sharing`, ensuring the running user's sharing rules apply to all queries. |
| **Object validation** | All object API names are validated against `Schema.getGlobalDescribe()` before any SOQL is built, preventing SOQL injection. |
| **Input sanitisation** | All user-supplied strings are escaped with `String.escapeSingleQuotes()`. Bind variables (`:parentRecordId`, `:safeTerm`) are used wherever possible. |
| **Field-level security** | Inline edit saves use Lightning Data Service (`updateRecord`), which enforces FLS and validation rules. |

---

## Test Coverage

The test class `SmartRelatedListControllerTest` includes 15 test methods covering:

- **getColumnDefinitions** — valid fields, empty fields (default to Name), picklist values, invalid object
- **getRelatedRecords** — row limit, offset, sort ascending/descending, search filter, invalid object, blank object
- **getTotalCount** — all records, search filter, invalid object
- **getObjectLabel** — valid object, invalid object

Run tests:

```bash
sf apex run test --class-names SmartRelatedListControllerTest --target-org <your-org-alias> --wait 10
```

---

## Limitations

- **Maximum 2,000 records** — the component loads up to 2,000 records in a single wire call. For objects with more related records, only the first 2,000 are available for search/sort/export.
- **Mobile** — `lightning-datatable` has known limitations on mobile devices. This component is optimised for desktop use.
- **Picklist inline edit** — uses a native HTML `<select>` instead of `lightning-combobox` due to event handling conflicts within custom datatable edit templates.

---

## Architecture

```
force-app/main/default/
├── classes/
│   ├── SmartRelatedListController.cls          # Apex controller (4 endpoints)
│   ├── SmartRelatedListController.cls-meta.xml
│   ├── SmartRelatedListControllerTest.cls      # Test class (15 methods, ≥75% coverage)
│   └── SmartRelatedListControllerTest.cls-meta.xml
├── lwc/
│   ├── smartRelatedList/
│   │   ├── smartRelatedList.js                 # Main component controller
│   │   ├── smartRelatedList.html               # Template
│   │   ├── smartRelatedList.css                # Scoped styles
│   │   └── smartRelatedList.js-meta.xml        # App Builder config & properties
│   └── customDatatable/
│       ├── customDatatable.js                  # Extends lightning-datatable (picklist support)
│       ├── customDatatable.js-meta.xml
│       ├── picklistTemplate.html               # Read-only picklist cell
│       └── picklistEditTemplate.html           # Edit-mode picklist cell (HTML <select>)
└── permissionsets/
    └── Smart_Related_List_User.permissionset-meta.xml
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Apex: SmartRelatedListController                           │
│  ┌──────────────────┐  ┌────────────────┐  ┌────────────┐  │
│  │ getColumnDefs    │  │ getRelatedRecs │  │ getObjLabel│  │
│  │ (field metadata, │  │ (dynamic SOQL, │  │ (plural    │  │
│  │  picklist values)│  │  up to 2000)   │  │  label)    │  │
│  └────────┬─────────┘  └───────┬────────┘  └─────┬──────┘  │
└───────────┼────────────────────┼──────────────────┼─────────┘
            │ @wire              │ @wire             │ @wire
┌───────────▼────────────────────▼──────────────────▼─────────┐
│  LWC: smartRelatedList                                      │
│                                                             │
│  allRecords → filteredRecords → sortedRecords → paginated   │
│  (server)     (search)          (column sort)    (page slice)│
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  c-custom-datatable (extends lightning-datatable)    │    │
│  │  + custom "picklist" column type                    │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## App Builder Properties

Configure everything from the Lightning App Builder properties panel — no hardcoded values.

| Property | Type | Required | Default | Description |
|---|---|---|---|---|
| **Card Title** | String | Yes | — | Header label displayed on the card (e.g. "Contacts"). |
| **Child Object API Name** | String | Yes | — | API name of the child object to query (e.g. `Contact`). |
| **Parent Lookup Field** | String | Yes | — | Lookup field on the child pointing to the parent (e.g. `AccountId`). |
| **Fields to Display** | String | Yes | — | Comma-separated field API names for columns (e.g. `Name,Email,Phone`). |
| **Sortable Fields** | String | No | All | Comma-separated field API names that should be sortable. Leave blank for all. |
| **Row Limit** | Integer | No | 10 | Number of records displayed per page. |
| **Enable Search** | Boolean | No | false | Show a search bar above the table. |
| **Enable Inline Edit** | Boolean | No | false | Allow inline cell editing with Save All / Cancel buttons. |
| **Enable CSV Export** | Boolean | No | false | Show an "Export CSV" button in the toolbar. |
| **Color Field** | String | No | — | API name of a text/picklist field used for row colour coding. |
| **Color Rules (JSON)** | String | No | — | JSON mapping field values to colour tokens (see [Row Colour Coding](#row-colour-coding)). |
| **Primary Action Label** | String | No | — | Label for a row-level action button (e.g. "Edit"). |
| **Enable New Record** | Boolean | No | false | Show a "New" button to create a child record. |
