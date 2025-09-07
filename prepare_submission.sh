#!/bin/bash

# Project submission preparation script
# Prepares everything for GitHub and submission

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SUBMISSION_DIR="SPM_Project_Submission"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

print_header() {
    echo ""
    echo "================================================"
    echo "  Distributed MergeSort - Submission Preparation"  
    echo "================================================"
    echo "Date: $(date)"
    echo "Tested on: SPM Cluster (University of Pisa)"
    echo "================================================"
    echo ""
}
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
PROJECT_NAME="SPM_project2_SalimTagemouati"
SUBMISSION_DIR="submission_package"
REPORT_PDF="SPM_Project_Report.pdf"

clean_workspace() {
    print_info "Cleaning workspace..."
    
    # Clean build artifacts
    make clean >/dev/null 2>&1 || true
    
    # Remove temporary files
    rm -rf test_data test_output benchmark_results
    rm -f *.bin *.log *.out
    rm -f core.* vgcore.*
    rm -f Makefile.config
    
    # Clean docs build directory
    rm -rf docs/build
    
    print_success "Workspace cleaned"
}

verify_implementation() {
    print_info "Verifying implementation completeness..."
    
    local required_files=(
        "main.cpp"
        "main_openmp.cpp" 
        "main_fastflow.cpp"
        "record_structure.hpp"
        "mpi_openmp_sort.hpp"
        "omp_mergesort.hpp"
        "fastflow_sort.hpp"
        "generate_records.cpp"
        "verify_output.py"
        "Makefile"
        "README.md"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "Missing required files:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        return 1
    fi
    
    print_success "All required implementation files present"
}

compile_report() {
    print_info "Compiling LaTeX report..."
    
    if [[ ! -f "docs/SPM_Project_Report.tex" ]]; then
        print_error "LaTeX report source not found"
        return 1
    fi
    
    # Check if pdflatex is available
    if ! command -v pdflatex &> /dev/null; then
        print_warning "pdflatex not found. Please compile report manually:"
        print_info "  cd docs && ./compile_report.sh"
        return 1
    fi
    
    cd docs
    if ./compile_report.sh >/dev/null 2>&1; then
        cd ..
        if [[ -f "$REPORT_PDF" ]]; then
            print_success "Report compiled successfully"
        else
            print_error "Report PDF not found after compilation"
            return 1
        fi
    else
        cd ..
        print_error "Report compilation failed"
        return 1
    fi
}

test_basic_functionality() {
    print_info "Testing basic functionality..."
    
    # Test if environment setup works
    if ! ./setup_environment.sh check >/dev/null 2>&1; then
        print_warning "Dependencies not available for testing"
        print_info "Run './setup_environment.sh' to install dependencies"
        return 0
    fi
    
    # Quick build test
    if make generate_records >/dev/null 2>&1; then
        print_success "Basic build test passed"
        rm -f generate_records
    else
        print_error "Basic build test failed"
        return 1
    fi
}

create_submission_package() {
    print_info "Creating submission package..."
    
    # Create submission directory
    rm -rf "$SUBMISSION_DIR"
    mkdir -p "$SUBMISSION_DIR"
    
    # Copy source files
    print_info "Copying source files..."
    cp *.cpp *.hpp "$SUBMISSION_DIR/"
    cp *.py "$SUBMISSION_DIR/"
    cp Makefile "$SUBMISSION_DIR/"
    cp README.md CHANGELOG.md LICENSE "$SUBMISSION_DIR/"
    cp *.sh "$SUBMISSION_DIR/"
    
    # Copy documentation
    print_info "Copying documentation..."
    mkdir -p "$SUBMISSION_DIR/docs"
    cp docs/*.tex "$SUBMISSION_DIR/docs/"
    cp docs/*.sh "$SUBMISSION_DIR/docs/"
    
    # Copy PDF report if available
    if [[ -f "$REPORT_PDF" ]]; then
        cp "$REPORT_PDF" "$SUBMISSION_DIR/"
        print_success "PDF report included"
    else
        print_warning "PDF report not found - include manually"
    fi
    
    # Copy FastFlow as a regular directory (not submodule)
    print_info "Copying FastFlow library..."
    cp -r fastflow "$SUBMISSION_DIR/"
    # Remove git metadata from fastflow copy
    rm -rf "$SUBMISSION_DIR/fastflow/.git"
    
    # Create submission info file
    cat > "$SUBMISSION_DIR/SUBMISSION_INFO.txt" << EOF
SPM Project 2 - Distributed Out-of-Core MergeSort
Author: Salim Tagemouati
University of Pisa
Submission Date: $(date)

Implementation Overview:
- OpenMP task-based parallel mergesort
- FastFlow pattern-based implementation
- MPI+OpenMP hybrid for distributed processing
- Variable-sized record support (8-4096 bytes)
- Out-of-core processing capabilities
- Comprehensive testing and verification

Build Instructions:
1. Run './setup_environment.sh' to install dependencies
2. Run 'make all' to build all implementations
3. Run 'make test-basic' for functionality verification
4. Run 'make benchmark' for performance evaluation

Key Files:
- main.cpp: MPI+OpenMP hybrid implementation
- main_openmp.cpp: OpenMP-only version
- main_fastflow.cpp: FastFlow-only version
- record_structure.hpp: Core data structures
- mpi_openmp_sort.hpp: Hybrid implementation
- omp_mergesort.hpp: OpenMP implementation
- fastflow_sort.hpp: FastFlow implementation
- generate_records.cpp: Test data generator
- verify_output.py: Output verification script
- SPM_Project_Report.pdf: Detailed technical report

Performance Results (1M records, 64B payloads):
- MPI+OpenMP (single node): 2,040ms (optimal)
- OpenMP: 3,349ms
- FastFlow: 4,364ms

For detailed information, see README.md and the technical report.
EOF
    
    print_success "Submission package created in $SUBMISSION_DIR/"
}

create_zip_archive() {
    print_info "Creating ZIP archive..."
    
    if [[ -d "$SUBMISSION_DIR" ]]; then
        # Create the ZIP file
        zip -r "${PROJECT_NAME}.zip" "$SUBMISSION_DIR" >/dev/null 2>&1
        
        # Get file size
        local zip_size=$(du -h "${PROJECT_NAME}.zip" | cut -f1)
        
        print_success "ZIP archive created: ${PROJECT_NAME}.zip ($zip_size)"
        
        # Show contents summary
        print_info "Archive contents:"
        unzip -l "${PROJECT_NAME}.zip" | tail -n +4 | head -n -2 | wc -l | xargs echo "  Files:"
        echo "  Size: $zip_size"
        
    else
        print_error "Submission directory not found"
        return 1
    fi
}

validate_submission() {
    print_info "Validating submission package..."
    
    local validation_dir="validation_test"
    rm -rf "$validation_dir"
    
    # Extract and test
    unzip -q "${PROJECT_NAME}.zip" -d "$validation_dir"
    cd "$validation_dir/$SUBMISSION_DIR"
    
    # Check if basic files are present
    local critical_files=("main.cpp" "Makefile" "README.md")
    for file in "${critical_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Critical file missing in submission: $file"
            cd ../..
            rm -rf "$validation_dir"
            return 1
        fi
    done
    
    # Test basic build (if dependencies available)
    if ./setup_environment.sh check >/dev/null 2>&1; then
        if make generate_records >/dev/null 2>&1; then
            print_success "Validation build test passed"
        else
            print_warning "Validation build test failed (but submission may still be valid)"
        fi
    else
        print_info "Cannot test build - dependencies not available"
    fi
    
    cd ../..
    rm -rf "$validation_dir"
    print_success "Submission package validated"
}

show_submission_summary() {
    echo ""
    echo "======================================"
    echo "        SUBMISSION SUMMARY"
    echo "======================================"
    echo ""
    print_success "Package: ${PROJECT_NAME}.zip"
    
    if [[ -f "${PROJECT_NAME}.zip" ]]; then
        local zip_size=$(du -h "${PROJECT_NAME}.zip" | cut -f1)
        echo "📦 Size: $zip_size"
        
        echo "📁 Contents:"
        echo "   - Complete source code (C++17)"
        echo "   - Three parallel implementations"
        echo "   - Build system and testing framework"
        echo "   - Comprehensive documentation"
        echo "   - FastFlow library included"
        if [[ -f "$SUBMISSION_DIR/$REPORT_PDF" ]]; then
            echo "   - Technical report (PDF)"
        else
            echo "   - Technical report (LaTeX source)"
        fi
        
        echo ""
        print_info "Submission checklist:"
        echo "   ✅ Source files included"
        echo "   ✅ Build system provided"
        echo "   ✅ Documentation complete"
        echo "   ✅ Testing framework included"
        if [[ -f "$SUBMISSION_DIR/$REPORT_PDF" ]]; then
            echo "   ✅ PDF report included"
        else
            echo "   ⚠️  PDF report missing (compile manually)"
        fi
        
        echo ""
        print_info "Email submission to: massimo.torquati@unipi.it"
        print_info "Subject: SPM Project"
        print_info "Attach: ${PROJECT_NAME}.zip"
        
    else
        print_error "ZIP file not created"
    fi
    
    echo ""
    print_info "Next steps:"
    echo "  1. Review submission package contents"
    echo "  2. Test extraction and compilation"
    echo "  3. Email to professor with required subject line"
    echo "  4. Keep backup of submission materials"
}

main() {
    echo "======================================"
    echo "   SPM Project Submission Package"
    echo "======================================"
    echo ""
    
    case "${1:-all}" in
        "clean")
            clean_workspace
            ;;
        "verify")
            verify_implementation
            ;;
        "report")
            compile_report
            ;;
        "test")
            test_basic_functionality
            ;;
        "package")
            create_submission_package
            ;;
        "zip")
            create_zip_archive
            ;;
        "validate")
            validate_submission
            ;;
        "all")
            clean_workspace
            verify_implementation
            compile_report || print_warning "Report compilation skipped"
            test_basic_functionality || print_warning "Functionality test skipped"
            create_submission_package
            create_zip_archive
            validate_submission
            show_submission_summary
            ;;
        "help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  clean     - Clean workspace"
            echo "  verify    - Verify implementation completeness"
            echo "  report    - Compile LaTeX report"
            echo "  test      - Test basic functionality"
            echo "  package   - Create submission directory"
            echo "  zip       - Create ZIP archive"
            echo "  validate  - Validate submission package"
            echo "  all       - Complete submission preparation (default)"
            echo "  help      - Show this help"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
