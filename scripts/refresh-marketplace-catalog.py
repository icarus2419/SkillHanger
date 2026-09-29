#!/usr/bin/env python3
"""Create the bundled browse catalog from publisher-owned public GitHub metadata.
No downloaded code is executed. Runtime refresh uses the Swift GitHubCatalog client.
"""
import concurrent.futures
import datetime
import json
import hashlib
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "SkillHanger-catalog-builder"})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()

def raw(repo, revision, path):
    return fetch(f"https://raw.githubusercontent.com/{repo}/{revision}/{path}")

def tree(repo):
    data = json.loads(fetch(f"https://api.github.com/repos/{repo}/git/trees/HEAD?recursive=1"))
    assert not data.get("truncated"), repo
    return data["sha"], data["tree"]

def category(text):
    text = text.lower()
    for label, words in [
        ("Security", ["security", "vulnerability", "audit", "threat"]),
        ("Testing", ["testing", "test-driven", "debugging", "verification", "playwright"]),
        ("Documents", ["document", "pdf", "xlsx", "spreadsheet", "pptx", "presentation", "docx"]),
        ("Design", ["design", "figma", "canva", "creative", "art", "image", "video", "game"]),
        ("Infrastructure", ["cloudflare", "infrastructure", "deployment", "devops", "vercel", "hosting"]),
        ("Data & research", ["data", "research", "science", "analytics", "visualization"]),
        ("Development", ["development", "developer", "code", "programming", "frontend", "sdk", "api", "git", "superpowers"]),
        ("Productivity", ["productivity", "planning", "notion", "calendar", "task", "comms", "writing"]),
    ]:
        if any(word in text for word in words):
            return label
    return "Integrations"

FEATURED = {"superpowers", "build-macos-apps", "frontend-design", "cloudflare", "figma", "code-review", "webapp-testing", "test-driven-development", "pdf", "react-best-practices"}
provenance = []

def plugin_catalog(agent, repo, manifest_path):
    sha, entries = tree(repo)
    manifest = json.loads(raw(repo, sha, manifest_path))
    provenance.append({"repository": repo, "revision": sha, "manifest": manifest_path})
    def convert(plugin):
        source = plugin.get("source", {})
        path, source_repo, revision = "", repo, sha
        if isinstance(source, str):
            path = source.removeprefix("./")
        elif isinstance(source, dict):
            if source.get("source") == "command":
                return None
            path = source.get("path", "").removeprefix("./")
            if source.get("url"):
                if not source["url"].startswith("https://github.com/"):
                    return None
                source_repo = source["url"].removeprefix("https://github.com/").removesuffix(".git").strip("/")
                revision = source.get("sha") or source.get("ref") or "HEAD"
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", source_repo):
            return None
        metadata = json.loads(raw(source_repo, revision, (path + "/" if path else "") + ".codex-plugin/plugin.json")) if agent == "codex" else plugin
        interface = metadata.get("interface", {})
        summary = interface.get("shortDescription") or metadata.get("description", "")
        if not summary:
            return None
        author = metadata.get("author", {}).get("name") or ("OpenAI catalog" if agent == "codex" else source_repo.split("/")[0])
        return dict(id=f'{agent}:{manifest["name"]}:{plugin["name"]}', name=plugin["name"],
                    title=interface.get("displayName") or plugin["name"].replace("-", " ").title(),
                    summary=summary, detail=interface.get("longDescription") or metadata.get("description") or summary,
                    author=author, category=category(plugin.get("category") or interface.get("category") or plugin["name"]),
                    kind="plugin", agents=[agent], repository=source_repo, path=path, revision=revision,
                    marketplace=manifest["name"], version=metadata.get("version"), license=metadata.get("license"),
                    keywords=metadata.get("keywords", []), featured=plugin["name"] in FEATURED,
                    logoName='catalog-' + hashlib.sha256(f'{agent}:{manifest["name"]}:{plugin["name"]}'.encode()).hexdigest()[:20] if interface.get('logo', '').lower().endswith('.png') else None)
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        return [entry for entry in pool.map(convert, manifest["plugins"]) if entry]

def skill_catalog(source):
    repo, root = source['repository'], source['root']
    sha, entries = tree(repo)
    provenance.append({"repository": repo, "revision": sha, "root": root})
    packages = {p['path']: p for p in source['packages']}
    paths = [e["path"] for e in entries if (e["path"] in {(p + '/' if p else '') + 'SKILL.md' for p in packages} if packages else e["path"].startswith(root + "/") and e["path"].endswith("/SKILL.md"))]
    assert len(paths) == len(packages) if packages else paths, repo
    def convert(path):
        text = raw(repo, sha, path).decode()
        frontmatter = text.split("---", 2)[1]
        fields, key = {}, None
        for line in frontmatter.splitlines():
            if line.startswith((" ", "\t")) and key:
                fields[key] += " " + line.strip()
            elif ":" in line:
                key, value = line.split(":", 1)
                value = value.strip()
                fields[key] = "" if value in (">", ">-", "|", "|-") else value.strip("\"'")
        name, summary = fields["name"], fields["description"].strip()
        directory = "" if path == "SKILL.md" else path.removesuffix("/SKILL.md")
        item = dict(id=repo + ":" + directory, name=name, title=name.replace("-", " ").title(),
                    summary=summary, detail=summary, author=repo.split("/")[0], category=category(name + " " + summary[:100]),
                    kind="skill", agents=["codex", "claude"], repository=repo, path=directory, revision=sha,
                    marketplace=None, version=None, license=fields.get("license"), keywords=[], featured=name in FEATURED,
                    community=source['community'], repositoryStars=source.get('repositoryStars'), popularityCheckedAt=source.get('popularityCheckedAt'))
        if directory in packages:
            item.update({k: v for k, v in packages[directory].items() if k != 'path'})
        return item
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        return list(pool.map(convert, paths))

if __name__ == "__main__":
    items = plugin_catalog("codex", "openai/plugins", ".agents/plugins/marketplace.json")
    items += plugin_catalog("claude", "anthropics/claude-plugins-official", ".claude-plugin/marketplace.json")
    sources = json.loads((ROOT / 'Sources/AgentAwakeApp/Assets/marketplace-sources.json').read_text())
    for source in sources:
        items += skill_catalog(source)
    assert len({i["id"] for i in items}) == len(items)
    (ROOT / "Sources/AgentAwakeApp/Assets/marketplace-catalog.json").write_text(json.dumps(items, indent=2) + "\n")
    report = {"generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(), "count": len(items), "sources": provenance}
    report_path = ROOT / "tasks/evidence/marketplace/catalog-provenance.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
