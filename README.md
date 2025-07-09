# BruteLocal

**BruteLocal.ps1** is a PowerShell-based credential brute-forcing utility designed for controlled internal use within assumed-breach, red team, or systems auditing scenarios. It enables security professionals to test local account passwords in a safe, lockout-aware manner by interleaving authentication attempts across users.

> **⚠ Disclaimer:** This script is intended for legitimate security testing and auditing by authorised personnel only. Usage against systems you do not own or have permission to test is illegal and unethical.

---

## ✨ Features

* Supports single usernames or user lists (including `DOMAIN\User` syntax)
* Batch-based password guessing with configurable pauses to avoid account lockout
* Outputs discovered credentials with optional file logging
* Supports quiet mode, verbose output, summary stats, and coloured console output
* Written in pure PowerShell 5.1 (compatible with Windows 10/11, Server 2016+)

---

## ⚡ Usage

```powershell
.\BruteLocal.ps1 -u users.txt -w rockyou.txt -g 9 -t 10 -v -s
```

### Parameters

| Parameter | Alias        | Description                                                               |
| --------- | ------------ | ------------------------------------------------------------------------- |
| `-u`      | `--user`     | A single username or path to a text file containing one username per line |
| `-w`      | `--wordlist` | Path to a password wordlist (default: `./wordlist.txt`)                   |
| `-g`      | `--guesses`  | Number of guesses per batch before sleeping (default: 9)                  |
| `-t`      | `--timeout`  | Minutes to wait between batches (default: 10)                             |
| `-o`      | `--output`   | Optional path to write results and summary                                |
| `-v`      | `--verbose`  | Verbose output (showing progress and debug messages)                      |
| `-q`      | `--quiet`    | Suppresses all output except success/failure                              |
| `-s`      | `--summary`  | Show a summary at the end of execution                                    |
| `-h`      | `--help`     | Displays help and usage information                                       |

---

## ⚙ Technical Details

### Logon Testing

BruteLocal uses native Windows API calls to verify credentials without spawning new processes. Specifically, it uses the `LogonUser` function from `advapi32.dll` via P/Invoke.

```csharp
[DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern bool LogonUser(
    string user, string domain, string pass,
    int type, int provider, out IntPtr token);
```

* **Logon type:** `2` (Interactive)
* **Logon provider:** `0` (Default)

Successful logins return a valid token, which is released immediately using:

```powershell
[Runtime.InteropServices.Marshal]::Release($token)
```

### Lockout Avoidance

The script interleaves attempts across users within a batch, ensuring that no single user receives more than `-g` attempts per cycle. After each batch, it sleeps for `-t` minutes to reset the lockout timer (based on `net accounts` policy).

### Token Cleanup

All successful tokens are explicitly released to avoid memory/resource leaks. No session is created or maintained.

---

## 📅 Example

```powershell
.\BruteLocal.ps1 -u .\users.txt -w .\common-passwords.txt -g 5 -t 15 -o results.log -v -s
```

---

## 💪 Ethical Use

This project exists to support defensive security testing, password hygiene audits, and training in responsible red team environments. Do not use this software for unauthorised access or malicious purposes.

---

## 🚀 Contributions

Pull requests, bug reports, and enhancements are welcome. Please ensure code is clean, documented, and tested on PowerShell 5.1 environments.

---

## 🌐 License

This project is licensed under the [MIT License](LICENSE).
