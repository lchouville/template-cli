# 📘 Translation & Mermaid SVG Generator
**Version v1.0.0**


## 📌 Overview
This Bash script is a full-featured CLI tool designed to:
- Generate SVG files from Mermaid (.mmd) sources
- Apply multi-language translations using {{KEY}} placeholders
- Validate translation consistency (missing / unused / duplicate keys)
- Automatically clean unused translation keys
- Install and verify required dependencies
- Provide clear visual feedback via progress bars and ETA

The script is built to be deterministic, readable, and automation-friendly.

## 🎯 Primary Use Cases
- Generating translated Mermaid diagrams
- Centralized JSON-based translation management
- Auditing and cleaning translation keys
- Producing ready-to-use SVG assets for applications or documentation

## 📂 Expected Project Structure
```sh
.
├── Documents/
│   ├── Edition-files/      # Source .mmd files
│   └── Graph/              # Generated SVG files
│
├── Translations/
│   ├── Mermaid/
│   │   ├── fr/
│   │   │   └── *.json
│   │   └── en/
│   │       └── *.json
│   ├── addedKey.json       # Missing keys detected
│   ├── deletedKey.json     # Removed unused keys
│   └── duplicateKey.json   # Duplicate keys across files
│
├── Scripts/
│   └── generate_mmd-svg.sh
│
└── package.json            # Node dependencies (mermaid-cli)
```

## ⚙️ Requirements

The script automatically checks for and installs the following tools if missing:

- Node.js (≥ 18 recommended)
- npm
- @mermaid-js/mermaid-cli
- jq
- bash ≥ 4

If node_modules are missing, the script will attempt to install them automatically.

##  🚀 Installation
```sh
chmod +x Scripts/generate_mmd-svg.sh
./Scripts/generate_mmd-svg.sh --install
```
This will:
- Verify Node.js and npm
- Install Mermaid CLI locally
- Validate required system tools

▶️ Usage
```sh
./Scripts/generate_mmd-svg.sh [options]
```
**Common options**
| Option              | Description                                  |
| ------------------- | -------------------------------------------- |
| `-h, --help`        | Show Using Details                           |
| `-a, --all`         | All (language and/or files)                  |
| `-lang`             | Language to use (e.g. `-en`, `-fr`)          |
| `-c, --clean`       | Automatically remove unused translation keys |
| `-i, --install`     | Install dependencies                         |
| `-x, --execute`     | auto generate after clean or validate        |
| `[files]`           | Files list to generate                       |

**Exemple**
```sh
./generate_mmd-svg.sh -fr -a # All File in French
./generate_mmd-svg.sh -a usercase.mmd architecture.mmd # All Languages for usercase and architecture file
./generate_mmd-svg.sh -a -a -v # All File and languages with validation mode only
./generate_mmd-svg.sh -a -a -v -c -x # All File and languages with validation and clean placeholder and execute after all
```

## 🔍 Validation Pipeline
1. Missing Keys
   - Detects placeholders used in Mermaid files but missing in translation JSON.

2. Unused Keys
   - Detects translation keys not referenced in any Mermaid file.

3. Duplicate Keys
   - Detects keys defined in multiple translation files.
   - Each step includes:
   - Progress bar
   - ETA
   - Structured output
   - Optional JSON export

## 🧹 Automatic Cleanup

When `--clean` is enabled:
- Unused keys are removed from translation files
- Their values and source files are stored in `deletedKey.json`
- Cleanup is atomic and safe (temp files + overwrite)

## 📊 Output
- SVG files are generated in `Documents/Graph/`
- Validation results are printed to stdout
- JSON reports are updated incrementally

##  📝 Changelog

### v1.0.1 #Minor-Update
- **Fix :**
  - Gererating files's progress bar
  - Spacing on some line
   
### v1.0.0 #Initial-Release
- **Add :**
  - Initial stable release
  - Mermaid SVG generation
  - Multi-language translation system
  - Validation: missing / unused / duplicate keys
  - Automatic cleanup support
  - Progress bars with ETA
  - CI-friendly behavior

## 👤 Authors & Collaborators

<table style="border-collapse: collapse; border: none; width: 100%">
  <!-- Column 1 - Max 3 profils -->
  <tr style="border: none">
    <!-- Contributeur 1 -->
    <td
      style="
        border: none;
        padding: 10px;
        text-align: center;
        vertical-align: top;
        width: 33%;
      "
    >
      <table
        style="border-collapse: collapse; border: none; display: inline-block"
      >
        <tr style="border: none">
          <td style="border: none; padding: 5px; text-align: center">
            <a href="https://github.com/lchouville">
              <img
                src="https://avatars.githubusercontent.com/u/51326118?v=4"
                width="100px;"
                alt="Luka Chouville"
              />
            </a>
          </td>
          <td style="border: none; padding: 5px; text-align: left">
            <p style="text-align: center;"><strong>Luka Chouville</strong></p>
            <p style="text-align: center;font-size:17px">Creator<br>Project Leader</p>
            <a
              href="https://www.linkedin.com/in/luka-chouville-6abb3717a"
              style="text-decoration: none"
            >
              <img
                src="https://img.icons8.com/color/20/000000/linkedin.png"
                style="vertical-align: middle"
              />
              LinkedIn </a
            ><br />
            <a
              href="https://github.com/lchouville"
              style="text-decoration: none"
            >
              <img
                src="https://img.icons8.com/ios-filled/20/000000/github.png"
                style="vertical-align: middle"
              />
              GitHub </a
            ><br />
            <a
              href="mailto:luka.chouville@laposte.net"
              style="text-decoration: none"
            >
              <img
                src="https://img.icons8.com/color/20/000000/gmail.png"
                style="vertical-align: middle"
              />
              luka.chouville.pro@gmail.com
            </a>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>