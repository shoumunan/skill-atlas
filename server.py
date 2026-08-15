#!/usr/bin/env python3
"""Read-only local server for Skill Atlas."""

from __future__ import annotations

import json
import os
import re
import sqlite3
import subprocess
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


APP_DIR = Path(__file__).resolve().parent
HOME = Path.home()
DB_PATH = HOME / ".cc-switch" / "cc-switch.db"
SOURCE_ROOT = HOME / ".cc-switch" / "skills"
MOUNT_ROOTS = {
    "codex": HOME / ".codex" / "skills",
    "claude": HOME / ".mirasim" / "skills",
}


CATEGORY_RULES = [
    ("基金与投研", ("fund", "基金", "stock", "股票", "finance", "投研", "研报", "wind")),
    ("社交内容", ("xiaohongshu", "douyin", "wechat", "social", "copywriter", "writer", "文案", "内容", "热点")),
    ("演示与文档", ("ppt", "slide", "deck", "docx", "document", "pdf", "spreadsheet", "excel", "notebook")),
    ("网页与自动化", ("browser", "playwright", "chrome", "scrap", "web-access", "computer-use", "automation", "phone-harness")),
    ("视觉与设计", ("image", "illustration", "canvas", "design", "frontend", "ui", "visual", "card", "gif")),
    ("数据与研究", ("data", "research", "analytics", "report", "kpi", "market", "metric", "scraper")),
    ("沟通与运营", ("email", "gmail", "outlook", "slack", "internal-comms", "account-executive", "strategy", "boss")),
    ("开发与工具", ("mcp", "api", "coding", "code", "github", "cloudflare", "vercel", "skill-creator", "plugin", "agent")),
    ("思考与协作", ("dbs", "think", "learn", "check", "review", "goal", "retro", "deconstruct")),
]


EXAMPLE_PROMPTS = {
    "fund-content-creative": [
        "帮我想 3 个能让基民共情的基金短视频创意",
        "围绕定投，做一套不说教的投教内容方案",
    ],
    "browser-use": [
        "打开这个网页，帮我填写表单并截图确认",
        "从这个页面提取表格数据，保留来源链接",
    ],
    "weekly-video-data": [
        "采集本周抖音、视频号和 B 站视频数据，更新现有周报",
        "核对这周发布的视频，并区分常规短视频和直播切片",
    ],
    "pptx": [
        "读取这份 PPT，帮我梳理每页核心信息",
        "用这份模板制作一份 12 页汇报，并保留原版式",
    ],
    "humanizer-zh": [
        "把这段中文改得更自然，去掉 AI 腔但不要改变意思",
        "审阅这篇文章，标出并修复生硬、空泛的表达",
    ],
}


def infer_category(name: str, description: str) -> str:
    haystack = f"{name} {description}".lower()
    for category, words in CATEGORY_RULES:
        if any(word in haystack for word in words):
            return category
    return "通用工具"


def read_frontmatter(skill_file: Path) -> dict[str, str]:
    try:
        text = skill_file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    frontmatter = text[3:end]
    result: dict[str, str] = {}
    for key in ("name", "description"):
        match = re.search(rf"(?ms)^{key}:\s*(.*?)(?=\n[a-zA-Z_-]+:|\Z)", frontmatter)
        if not match:
            continue
        value = match.group(1).strip().strip('"\'')
        if value in ("|", ">"):
            value = ""
        value = re.sub(r"\s+", " ", value).strip()
        if value:
            result[key] = value
    return result


def mount_state(root: Path, directory: str, enabled: bool, source: Path) -> dict:
    target = root / directory
    exists = target.exists()
    is_link = target.is_symlink()
    if enabled:
        if not exists:
            status = "broken" if is_link else "missing"
        elif not is_link:
            status = "directory"
        else:
            try:
                status = "ok" if os.path.samefile(target, source) else "wrong"
            except OSError:
                status = "wrong"
    else:
        status = "unexpected" if exists or is_link else "disabled"
    return {
        "enabled": bool(enabled),
        "status": status,
        "path": str(target),
        "isLink": is_link,
        "target": str(target.resolve(strict=False)) if is_link else "",
    }


def derive_when(name: str, description: str, category: str) -> str:
    clean = re.sub(r"\s+", " ", description).strip()
    chinese_match = re.search(r"(当用户[^。；]{8,180}[。；]?)", clean)
    if chinese_match:
        return chinese_match.group(1).rstrip("；")
    use_match = re.search(r"(?i)(Use (?:this skill )?when[^.]{8,180}\.)", clean)
    if use_match:
        return use_match.group(1)
    templates = {
        "基金与投研": "当任务涉及基金内容、金融数据、投资研究或市场信息时调用。",
        "社交内容": "当你要策划、撰写或改造社交媒体内容时调用。",
        "演示与文档": "当任务需要读取、创建或修改演示稿与办公文档时调用。",
        "网页与自动化": "当任务需要操作真实网页、采集页面信息或自动执行步骤时调用。",
        "视觉与设计": "当任务需要界面、图片、视觉物料或设计判断时调用。",
        "数据与研究": "当任务需要采集、验证、分析数据或形成研究结论时调用。",
        "沟通与运营": "当任务涉及沟通材料、客户协作或内容运营时调用。",
        "开发与工具": "当任务涉及代码、API、MCP、部署或开发工具时调用。",
        "思考与协作": "当问题需要结构化思考、复盘、审查或多人协作时调用。",
    }
    return templates.get(category, f"当你的任务与 {name} 描述的能力直接相关时调用。")


def derive_examples(name: str, category: str) -> list[str]:
    if name in EXAMPLE_PROMPTS:
        return EXAMPLE_PROMPTS[name]
    examples = {
        "基金与投研": f"请使用 {name} 帮我完成这项基金或投研任务：<写清目标和时间范围>",
        "社交内容": f"请使用 {name} 把这份素材做成适合目标平台发布的内容",
        "演示与文档": f"请使用 {name} 处理这个文件，并保持原有结构和格式",
        "网页与自动化": f"请使用 {name} 打开目标页面，完成操作并给我验证结果",
        "视觉与设计": f"请使用 {name} 根据这份需求生成或优化视觉方案",
        "数据与研究": f"请使用 {name} 收集并验证这项数据，标明口径和来源",
        "沟通与运营": f"请使用 {name} 整理这次沟通，并输出可执行的下一步",
        "开发与工具": f"请使用 {name} 完成这个技术任务，并验证结果",
        "思考与协作": f"请使用 {name} 分析这个问题，指出关键判断和下一步",
    }
    return [examples.get(category, f"请使用 {name} 帮我完成：<描述你的目标、素材和交付格式>"),
            f"这个任务适合用 {name} 吗？请先判断，再按它的流程执行"]


def scan_skills() -> dict:
    if not DB_PATH.exists():
        raise FileNotFoundError(f"找不到 CC Switch 数据库：{DB_PATH}")
    connection = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    rows = connection.execute("SELECT * FROM skills ORDER BY name COLLATE NOCASE").fetchall()
    connection.close()

    skills = []
    health_counts = {"healthy": 0, "warning": 0, "error": 0}
    verified_counts = {"codex": 0, "claude": 0}
    for row in rows:
        item = dict(row)
        source = SOURCE_ROOT / item["directory"]
        skill_file = source / "SKILL.md"
        metadata = read_frontmatter(skill_file)
        description = (item.get("description") or metadata.get("description") or "暂无用途说明").strip()
        category = infer_category(item["name"], description)
        mounts = {
            "codex": mount_state(MOUNT_ROOTS["codex"], item["directory"], bool(item["enabled_codex"]), source),
            "claude": mount_state(MOUNT_ROOTS["claude"], item["directory"], bool(item["enabled_claude"]), source),
        }
        for platform in verified_counts:
            if mounts[platform]["status"] == "ok":
                verified_counts[platform] += 1

        problems = []
        severity = "healthy"
        if not source.exists():
            problems.append("源目录缺失")
            severity = "error"
        if not skill_file.is_file():
            problems.append("SKILL.md 缺失")
            severity = "error"
        for label, mount in (("Codex", mounts["codex"]), ("Claude", mounts["claude"])):
            if mount["status"] in ("missing", "broken", "wrong"):
                problems.append(f"{label} 挂载{ {'missing':'缺失','broken':'断链','wrong':'目标错误'}[mount['status']] }")
                severity = "error"
            elif mount["status"] in ("directory", "unexpected"):
                problems.append(f"{label} { '是普通目录' if mount['status'] == 'directory' else '存在未启用挂载' }")
                if severity != "error":
                    severity = "warning"
        if metadata.get("name") and metadata["name"] != item["name"]:
            problems.append("名称元数据不一致")
            if severity != "error":
                severity = "warning"
        health_counts[severity] += 1

        platforms = [
            label for key, label in (
                ("enabled_codex", "Codex"),
                ("enabled_claude", "Claude"),
                ("enabled_gemini", "Gemini"),
                ("enabled_opencode", "OpenCode"),
                ("enabled_hermes", "Hermes"),
                ("enabled_grokbuild", "GrokBuild"),
            ) if item.get(key)
        ]
        modified_at = int(skill_file.stat().st_mtime) if skill_file.exists() else 0
        skills.append({
            "id": item["id"],
            "name": item["name"],
            "directory": item["directory"],
            "description": description,
            "category": category,
            "whenToUse": derive_when(item["name"], description, category),
            "examplePrompts": derive_examples(item["name"], category),
            "platforms": platforms,
            "sourcePath": str(source),
            "skillFile": str(skill_file),
            "repo": "/".join(filter(None, (item.get("repo_owner"), item.get("repo_name")))) or "本地 Skill",
            "installedAt": item.get("installed_at") or 0,
            "updatedAt": item.get("updated_at") or modified_at,
            "health": severity,
            "problems": problems,
            "mounts": mounts,
            "searchText": f"{item['name']} {description} {category}".lower(),
        })

    enabled_counts = {
        "codex": sum(bool(row["enabled_codex"]) for row in rows),
        "claude": sum(bool(row["enabled_claude"]) for row in rows),
        "grokbuild": sum(bool(row["enabled_grokbuild"]) for row in rows),
    }
    return {
        "skills": skills,
        "summary": {
            "total": len(skills),
            "enabled": enabled_counts,
            "verified": verified_counts,
            "health": health_counts,
            "sourceRoot": str(SOURCE_ROOT),
            "database": str(DB_PATH),
            "scannedAt": datetime.now().astimezone().isoformat(timespec="seconds"),
            "readOnly": True,
        },
    }


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(APP_DIR), **kwargs)

    def log_message(self, fmt: str, *args) -> None:
        print(f"[Skill Atlas] {fmt % args}")

    def end_headers(self) -> None:
        if not urlparse(self.path).path.startswith("/api/"):
            self.send_header("Cache-Control", "no-store, max-age=0")
        super().end_headers()

    def send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/skills":
            try:
                self.send_json(scan_skills())
            except Exception as exc:  # show actionable local error in the UI
                self.send_json({"error": str(exc)}, 500)
            return
        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/api/open-folder":
            self.send_json({"error": "Not found"}, 404)
            return
        query = parse_qs(parsed.query)
        requested = Path(query.get("path", [""])[0]).expanduser().resolve(strict=False)
        try:
            requested.relative_to(SOURCE_ROOT.resolve())
        except (ValueError, OSError):
            self.send_json({"error": "只允许打开 CC Switch Skill 目录"}, 403)
            return
        if not requested.exists():
            self.send_json({"error": "目录不存在"}, 404)
            return
        subprocess.Popen(["open", str(requested)])
        self.send_json({"ok": True})


def main() -> None:
    host = os.environ.get("SKILL_ATLAS_HOST", "127.0.0.1")
    port = int(os.environ.get("SKILL_ATLAS_PORT", "4178"))
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"Skill Atlas 已启动：http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
