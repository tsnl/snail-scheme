#!/usr/bin/env python3
"""Recreate the frozen, original-text corpus; never run as part of a benchmark."""

from hashlib import sha256
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "corpus"
PHRASES = ("copper owl", "river lantern", "winter fern", "silent comet")
CHECKS = "aaaa\ncopper owl\nriver lantern\nwinter fern\nsilent comet\n"


def paragraph(document, line):
    phrase = PHRASES[(document + 3 * line) % len(PHRASES)]
    return (f"Station {document:02d}, entry {line:02d}: the {phrase} marks a quiet path. "
            "Keep the map beside the window; record the weather before leaving.\n")


def document_text(document):
    header = f"Field notebook {document:03d}. A fictional archive for literal search.\n"
    return header + "".join(paragraph(document, line)
                            for line in range(32 + document % 17))


def write_document(name, text):
    data = text.encode("utf-8")
    (ROOT / name).write_bytes(data)
    return f"{sha256(data).hexdigest()}  {name}\n"


def corpus_summary():
    matches = checksum = characters = 0
    for document in range(64):
        text = document_text(document)
        for query, phrase in enumerate((*PHRASES, "absent phrase")):
            count = text.count(phrase)
            matches += count
            checksum += (document + 1) * (query + 1) * count
            characters += len(text)
    return matches, checksum, characters


def main():
    ROOT.mkdir(exist_ok=True)
    hashes = [write_document(f"document-{number:03d}.txt", document_text(number))
              for number in range(64)]
    hashes.append(write_document("checks.txt", CHECKS))
    (ROOT / "SHA256SUMS").write_text("".join(hashes), encoding="ascii")
    print("matches, weighted checksum, characters:", corpus_summary())


if __name__ == "__main__":
    main()
