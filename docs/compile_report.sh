#!/bin/bash

# LaTeX Report Compilation Script
# Author: Salim Tagemouati

set -e

REPORT_FILE="SPM_Project_Report.tex"
OUTPUT_DIR="../"

echo "🔧 Compiling LaTeX report..."

# Check if LaTeX is available
if ! command -v pdflatex &> /dev/null; then
    echo "❌ pdflatex not found. Please install LaTeX."
    echo "   On macOS: brew install --cask mactex"
    echo "   On Ubuntu: sudo apt-get install texlive-latex-extra"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p build

echo "📄 Running pdflatex (first pass)..."
pdflatex -output-directory=build -interaction=nonstopmode "$REPORT_FILE" > /dev/null

echo "📄 Running pdflatex (second pass for references)..."
pdflatex -output-directory=build -interaction=nonstopmode "$REPORT_FILE" > /dev/null

echo "📄 Running pdflatex (third pass for table of contents)..."
pdflatex -output-directory=build -interaction=nonstopmode "$REPORT_FILE" > /dev/null

# Copy PDF to main directory
cp "build/SPM_Project_Report.pdf" "$OUTPUT_DIR"

# Clean up auxiliary files but keep the PDF
rm -f build/*.aux build/*.log build/*.toc build/*.out build/*.fdb_latexmk build/*.fls build/*.synctex.gz

echo "✅ Report compiled successfully!"
echo "📁 Output: SPM_Project_Report.pdf"

# Check if PDF viewer is available and offer to open
if command -v open &> /dev/null; then
    read -p "🔍 Open PDF? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "$OUTPUT_DIR/SPM_Project_Report.pdf"
    fi
elif command -v xdg-open &> /dev/null; then
    read -p "🔍 Open PDF? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        xdg-open "$OUTPUT_DIR/SPM_Project_Report.pdf"
    fi
fi

echo "📋 LaTeX compilation complete!"
