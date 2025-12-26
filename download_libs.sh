#!/bin/bash
mkdir -p "MarkDown Mac/WebResources/lib/codemirror"
mkdir -p "MarkDown Mac/WebResources/lib/codemirror/mode"
mkdir -p "MarkDown Mac/WebResources/lib/codemirror/theme"

cd "MarkDown Mac/WebResources/lib/codemirror"

# Core
curl -O https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/codemirror.min.js
curl -O https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/codemirror.min.css

# Themes
cd theme
curl -O https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/theme/dracula.min.css
curl -O https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/theme/xq-light.min.css
cd ..

# Modes
cd mode
mkdir markdown xml javascript
curl -o markdown/markdown.min.js https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/mode/markdown/markdown.min.js
curl -o xml/xml.min.js https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/mode/xml/xml.min.js
curl -o javascript/javascript.min.js https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/mode/javascript/javascript.min.js
cd ..

# Addons
mkdir -p addon/edit addon/selection addon/display
curl -o addon/edit/continuelist.min.js https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/addon/edit/continuelist.min.js
curl -o addon/edit/closebrackets.min.js https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/addon/edit/closebrackets.min.js
curl -o addon/selection/active-line.min.js https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/addon/selection/active-line.min.js
curl -o addon/display/placeholder.min.js https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.13/addon/display/placeholder.min.js

# Markdown-It & Plugins
cd ../..
mkdir -p "lib/markdown-it"
cd "lib/markdown-it"
curl -O https://cdn.jsdelivr.net/npm/markdown-it@13.0.1/dist/markdown-it.min.js
curl -O https://cdn.jsdelivr.net/npm/markdown-it-emoji@2.0.2/dist/markdown-it-emoji.min.js
curl -O https://cdn.jsdelivr.net/npm/markdown-it-sub@1.0.0/dist/markdown-it-sub.min.js
curl -O https://cdn.jsdelivr.net/npm/markdown-it-sup@1.0.0/dist/markdown-it-sup.min.js
curl -O https://cdn.jsdelivr.net/npm/markdown-it-footnote@3.0.3/dist/markdown-it-footnote.min.js

# Highlight.js
cd ../..
mkdir -p "lib/highlight"
cd "lib/highlight"
curl -O https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/highlight.min.js
curl -o github-dark.min.css https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/styles/github-dark.min.css

# Mermaid
cd ../..
mkdir -p "lib/mermaid"
cd "lib/mermaid"
curl -O https://cdn.jsdelivr.net/npm/mermaid@10.2.4/dist/mermaid.min.js
