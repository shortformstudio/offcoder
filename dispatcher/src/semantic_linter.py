"""
Semantic Pre-Commit Linter for Offcoder Staging Ring
Performs zero-latency AST syntax, unresolved import, and structural checks
before deliverables are accepted into staging or presented to the developer.
"""

from __future__ import annotations

import ast
import json
import re
from typing import Any, Dict, List, Optional


class SemanticPreCommitLinter:
    """Validates code snippets prior to staging."""

    @staticmethod
    def lint(code: str, file_path: Optional[str] = None, lang_hint: Optional[str] = None) -> Dict[str, Any]:
        """
        Inspects code content and returns a structured diagnostic report.
        Report format:
        {
            "status": "CLEAN" | "WARNING" | "ERROR",
            "syntax_valid": bool,
            "diagnostics": [
                {
                    "line": int,
                    "col": int,
                    "severity": "error" | "warning",
                    "code": str,
                    "message": str,
                    "remediation": str
                }
            ]
        }
        """
        if not code or not code.strip():
            return {
                "status": "WARNING",
                "syntax_valid": False,
                "diagnostics": [
                    {
                        "line": 1,
                        "col": 1,
                        "severity": "warning",
                        "code": "EMPTY_PAYLOAD",
                        "message": "Candidate payload is completely empty.",
                        "remediation": "Provide substantive code block before staging.",
                    }
                ],
            }

        # Deduce language
        lang = (lang_hint or "").lower()
        if not lang and file_path:
            ext = file_path.rsplit(".", 1)[-1].lower() if "." in file_path else ""
            if ext in ("py", "pyw"):
                lang = "python"
            elif ext in ("js", "mjs", "cjs"):
                lang = "javascript"
            elif ext in ("ts", "tsx"):
                lang = "typescript"
            elif ext in ("swift",):
                lang = "swift"
            elif ext in ("json",):
                lang = "json"
            elif ext in ("html", "htm"):
                lang = "html"

        if not lang:
            # Heuristic detection
            if "import " in code and ("def " in code or "class " in code or "__name__" in code):
                lang = "python"
            elif "func " in code or ("var " in code and "import SwiftUI" in code):
                lang = "swift"
            elif "const " in code or "export " in code or "function " in code or "=>" in code:
                lang = "javascript"
            elif code.strip().startswith("{") and code.strip().endswith("}"):
                lang = "json"

        diagnostics: List[Dict[str, Any]] = []

        if lang == "python":
            diagnostics.extend(SemanticPreCommitLinter._lint_python(code))
        elif lang in ("javascript", "typescript"):
            diagnostics.extend(SemanticPreCommitLinter._lint_js_ts(code))
        elif lang == "swift":
            diagnostics.extend(SemanticPreCommitLinter._lint_swift(code))
        elif lang == "json":
            diagnostics.extend(SemanticPreCommitLinter._lint_json(code))
        else:
            # Generic delimiter check
            diagnostics.extend(SemanticPreCommitLinter._lint_delimiters(code))

        has_error = any(d["severity"] == "error" for d in diagnostics)
        has_warning = any(d["severity"] == "warning" for d in diagnostics)

        status = "ERROR" if has_error else ("WARNING" if has_warning else "CLEAN")

        return {
            "status": status,
            "syntax_valid": not has_error,
            "diagnostics": diagnostics,
        }

    @staticmethod
    def _lint_python(code: str) -> List[Dict[str, Any]]:
        diagnostics = []
        try:
            tree = ast.parse(code)
            # Check for suspicious wildcards or unclosed stubs
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom):
                    if any(alias.name == "*" for alias in node.names):
                        diagnostics.append({
                            "line": getattr(node, "lineno", 1),
                            "col": getattr(node, "col_offset", 0),
                            "severity": "warning",
                            "code": "W001_WILDCARD_IMPORT",
                            "message": f"Wildcard import 'from {node.module} import *' pollutes namespace.",
                            "remediation": "Explicitly import required symbols.",
                        })
                # Check for empty except blocks
                if isinstance(node, ast.ExceptHandler):
                    if len(node.body) == 1 and isinstance(node.body[0], ast.Pass):
                        diagnostics.append({
                            "line": getattr(node, "lineno", 1),
                            "col": getattr(node, "col_offset", 0),
                            "severity": "warning",
                            "code": "W002_SILENT_EXCEPT",
                            "message": "Silent try-except block suppresses runtime anomalies.",
                            "remediation": "Log or bubble up exceptions with jlog().",
                        })
        except SyntaxError as e:
            diagnostics.append({
                "line": e.lineno or 1,
                "col": e.offset or 0,
                "severity": "error",
                "code": "E999_SYNTAX",
                "message": f"SyntaxError: {e.msg}",
                "remediation": f"Verify syntax near line {e.lineno}: '{e.text.strip() if e.text else ''}'",
            })
        except Exception as e:
            diagnostics.append({
                "line": 1,
                "col": 0,
                "severity": "error",
                "code": "E998_PARSER_FAILURE",
                "message": f"AST parser error: {str(e)}",
                "remediation": "Review code formatting and indentation.",
            })

        return diagnostics

    @staticmethod
    def _lint_js_ts(code: str) -> List[Dict[str, Any]]:
        diagnostics = []
        # Check delimiter balance
        diagnostics.extend(SemanticPreCommitLinter._lint_delimiters(code))
        
        # Check common unclosed regex/quotes or template literals
        backtick_count = code.count("`")
        if backtick_count % 2 != 0:
            diagnostics.append({
                "line": code.count("\n") + 1,
                "col": 0,
                "severity": "error",
                "code": "E101_UNCLOSED_TEMPLATE",
                "message": "Unterminated template literal (`).",
                "remediation": "Close template string literal with '`'.",
            })

        # Check for unresolved relative imports
        for i, line in enumerate(code.splitlines(), start=1):
            if re.search(r"import\s+.*\s+from\s+['\"][.]{1,2}/.*undefined", line):
                diagnostics.append({
                    "line": i,
                    "col": 0,
                    "severity": "error",
                    "code": "E102_UNDEFINED_IMPORT",
                    "message": "Import path references an undefined module.",
                    "remediation": "Verify target module file exists.",
                })
        return diagnostics

    @staticmethod
    def _lint_swift(code: str) -> List[Dict[str, Any]]:
        diagnostics = []
        diagnostics.extend(SemanticPreCommitLinter._lint_delimiters(code))
        for i, line in enumerate(code.splitlines(), start=1):
            if re.search(r"\bguard\b.*else\s*$", line.strip()):
                diagnostics.append({
                    "line": i,
                    "col": 0,
                    "severity": "error",
                    "code": "E201_INCOMPLETE_GUARD",
                    "message": "Guard statement missing closure '{ return / throw }'.",
                    "remediation": "Provide an exit block for the guard condition.",
                })
        return diagnostics

    @staticmethod
    def _lint_json(code: str) -> List[Dict[str, Any]]:
        diagnostics = []
        try:
            json.loads(code)
        except json.JSONDecodeError as e:
            diagnostics.append({
                "line": e.lineno,
                "col": e.colno,
                "severity": "error",
                "code": "E301_JSON_DECODE",
                "message": f"JSONDecodeError: {e.msg}",
                "remediation": f"Fix JSON syntax near line {e.lineno}, col {e.colno}.",
            })
        return diagnostics

    @staticmethod
    def _lint_delimiters(code: str) -> List[Dict[str, Any]]:
        diagnostics = []
        pairs = {"(": ")", "{": "}", "[": "]"}
        inv = {v: k for k, v in pairs.items()}
        stack: List[tuple[str, int, int]] = []

        line_num = 1
        col_num = 1
        in_single_line_comment = False
        in_string: Optional[str] = None

        for idx, char in enumerate(code):
            if char == "\n":
                line_num += 1
                col_num = 1
                in_single_line_comment = False
                continue

            if in_single_line_comment:
                col_num += 1
                continue

            # Basic comment checking
            if char == "/" and idx + 1 < len(code) and code[idx + 1] == "/":
                in_single_line_comment = True
                col_num += 1
                continue
            if char == "#":
                in_single_line_comment = True
                col_num += 1
                continue

            # Strings
            if char in ("'", '"') and (idx == 0 or code[idx - 1] != "\\"):
                if in_string == char:
                    in_string = None
                elif in_string is None:
                    in_string = char
                col_num += 1
                continue

            if in_string is not None:
                col_num += 1
                continue

            if char in pairs:
                stack.append((char, line_num, col_num))
            elif char in inv:
                expected_open = inv[char]
                if not stack or stack[-1][0] != expected_open:
                    diagnostics.append({
                        "line": line_num,
                        "col": col_num,
                        "severity": "error",
                        "code": "E001_MISMATCHED_DELIMITER",
                        "message": f"Mismatched closing delimiter '{char}'.",
                        "remediation": f"Ensure correct opening '{expected_open}' before line {line_num}.",
                    })
                else:
                    stack.pop()

            col_num += 1

        for unclosed, l, c in stack:
            diagnostics.append({
                "line": l,
                "col": c,
                "severity": "error",
                "code": "E002_UNCLOSED_DELIMITER",
                "message": f"Unclosed delimiter '{unclosed}'.",
                "remediation": f"Close with '{pairs[unclosed]}' matching line {l}.",
            })

        return diagnostics
