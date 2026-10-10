#!/usr/bin/env python3
"""Generate static information pages from the app's bundled documents.

Unapproved text can only be rendered for local review, never silently published.
No analytics, remote fonts, scripts or external images are used.
"""
import argparse
import html
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
DOCUMENTS = ROOT / "OpenWorkRemote/Resources/Information"


def paragraphs(text):
    blocks = []
    for paragraph in text.strip().split("\n\n"):
        if paragraph.startswith("## "):
            title, _, body = paragraph.partition("\n")
            blocks.append("<section><h2>" + html.escape(title[3:]) + "</h2><p>" + html.escape(body) + "</p></section>")
        else:
            blocks.append("<p>" + html.escape(paragraph).replace("\n", "<br>") + "</p>")
    return "\n".join(blocks)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--allow-draft", action="store_true", help="Local review only")
    args = parser.parse_args()
    manifest = json.loads((DOCUMENTS / "manifest.json").read_text())
    if not manifest["policyApproved"] and not args.allow_draft:
        parser.error("Policy approval is required before generating publishable pages")
    if not args.allow_draft and not manifest.get("supportEmail"):
        parser.error("An approved public support email is required before publication")
    email = manifest.get("supportEmail")
    if email and not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", email):
        parser.error("Invalid support email")
    args.output.mkdir(parents=True, exist_ok=True)
    css = """html{color-scheme:light dark}body{font:1.1rem/1.65 system-ui,sans-serif;margin:0;background:Canvas;color:CanvasText}header,main,footer{max-width:48rem;margin:auto;padding:1.5rem}nav{display:flex;gap:1.25rem;flex-wrap:wrap}a{color:LinkText;text-underline-offset:.2em}a:focus-visible{outline:3px solid #5477ff;outline-offset:5px}h1{line-height:1.15;font-size:clamp(2rem,6vw,3rem)}h2{line-height:1.3}p,li{overflow-wrap:anywhere}section{margin-top:2rem}footer{border-top:1px solid GrayText;font-size:.95rem}.draft{border:2px solid #5477ff;padding:1rem}small{font-size:.9rem}"""
    (args.output / "style.css").write_text(css + "\n")
    pages = {
        "": ("PocketWork", "## Your computer. Your chats.\nPocketWork is an independently maintained iOS companion for OpenWork, maintained by Salty Panda LLC. The current private beta requires the tested OpenWork preview and Tailscale on your phone and computer. Public App Store availability is not announced.\n\n## Help and privacy\nRead the support page for connection steps and safe ways to report a problem. The privacy page explains where your data goes and how to remove local copies."),
        "privacy": ("Privacy policy", (DOCUMENTS / "privacy.txt").read_text()),
        "support": ("Support", (DOCUMENTS / "help.txt").read_text()),
        "terms": ("Terms of use", (DOCUMENTS / "terms.txt").read_text()),
        "licenses": ("Source license and notices", (DOCUMENTS / "notices.txt").read_text() + "\n\n" + (DOCUMENTS / "sourceLicense.txt").read_text()),
    }
    for route, (title, text) in pages.items():
        prefix = "../" if route else "./"
        nav = f'<nav aria-label="Information"><a href="{prefix}">PocketWork</a><a href="{prefix}support/">Support</a><a href="{prefix}privacy/">Privacy</a><a href="{prefix}terms/">Terms</a><a href="{prefix}licenses/">Licenses</a></nav>'
        draft = '<p class="draft">Private review draft. These pages are not approved for publication.</p>' if args.allow_draft else ""
        contact = f'<p>Salty Panda LLC. <a href="{html.escape(manifest["supportURL"], quote=True)}">Support on GitHub</a>. Issues are public; leave out private information.</p>'
        if email:
            contact += f'<p>Contact: <a href="mailto:{html.escape(email, quote=True)}">{html.escape(email)}</a></p>'
        else:
            contact += '<p class="draft">Public support contact is awaiting approval.</p>'
        if route == "support":
            contact += f'<p>For security concerns, use <a href="https://github.com/BitL8-ByteShort/openwork-remote-ios/security/advisories/new">private vulnerability reporting</a>.</p>'
        page = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)} | PocketWork</title><meta name="description" content="PocketWork information from Salty Panda LLC"><link rel="stylesheet" href="{prefix}style.css"></head><body><header>{nav}</header><main>{draft}<h1>{html.escape(title)}</h1>{paragraphs(text)}</main><footer>{contact}<p>Independent companion for OpenWork. No official affiliation.</p></footer></body></html>\n'
        directory = args.output / route
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "index.html").write_text(page)
    (args.output / ".nojekyll").write_text("")
    print("Generated 5 static information pages" + (" for private review" if args.allow_draft else ""))


if __name__ == "__main__":
    main()
