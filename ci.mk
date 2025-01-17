ci_dir?=$(realpath $(root_dir)/ci)
cur_dir:=$(realpath .)

CPPCHECK?=cppcheck
CLANG_VERSION?=12
CLANG-FORMAT?=clang-format-$(CLANG_VERSION)
CLANG-TIDY?=clang-tidy-$(CLANG_VERSION)

.SECONDEXPANSION:

# Git Commit message linting
# Checks if the commit messages follow the conventional commit style from 
# GITLINT_BASE to the last commit. For example, for checking the last two commits:
#    make gitlint GITLINT_BASE=HEAD~2

gitlint:
	@gitlint -C $(ci_dir)/.gitlint --commits $(GITLINT_BASE)..

#############################################################################

# License Checking
# Checks if the provided source file have a SPDX license identifier following
# the provided SPDX license expriession.
#    make license-check
# @param string of SPDX expression of the allowed license for the files defined 
#     in the second param
# @param space-separated list of source files (any kind)
# @example $(call ci, license, "Apache-2.0 OR MIT", file1.c file.rs file.h file.mk)

license_check_script:=$(ci_dir)/license_check.py

license:
	@$(license_check_script) -l $(spdx_expression) $(lincense_check_files)

define license
spdx_expression:=$1
lincense_check_files:=$2
endef

#############################################################################

# Python linting
# Checks if the provided python scrpits for syntax and format:
#    make pylint
# @param space-separated list of python files
# @example $(call ci, pylint, file1.py file2.py)

pylintrc:=$(ci_dir)/.pylintrc

pylint: $(pylintrc)
	@pylint $(_python_scritps)

define pylint
_python_scritps+=$1
endef

#############################################################################

# YAML linting
# Checks if the provided yaml files for syntax and format:
#    make yamllint
# @param space-separated list of yaml files
# @example $(call ci, yamllint, file1.yaml file2.yml)

yamllint:
	@yamllint --strict $(_yaml_files)
.PHONY:yamllint

define yamllint
_yaml_files+=$1
endef

#############################################################################

# C Formatting
# Provides two make targets:
#    make format-check # checks if the provided C files are formated correctly
#    make format # formats the provided C files 
# @param space-separated list of C source or header files
# @example $(call ci, format, file1.c fil2.c file3.h)

clang_format_flags:=--style=file
format_file:=$(cur_dir)/.clang-format
original_format_file:=$(ci_dir)/.clang-format

$(format_file): $(original_format_file)
	@cp $< $@

format: $(format_file)
	@$(CLANG-FORMAT) $(clang_format_flags) -i $(_format_files)

format-check: $(format_file)
	@diff <(cat $(_format_files)) <($(CLANG-FORMAT) $(clang_format_flags) $(_format_files))

format-clean:
	-@rm -f $(format_file)

clean: format-clean

.PHONY: format format-check format-clean
non_build_targets+=format format-check format-clean

define format
_format_files+=$1
endef

#############################################################################

# Clang-tidy linter
# To run the tidy linter:
#    make tidy
# @pre the make variable `clang-arch` must be defined if using the tidy rule
#    with a valid target fot the clang compiler
# @pre the make variable `CPPFLAGS` must be defined with all pre-processor
# options, specially the include directory -paths (e.g -I/my/include/dir/inc)
# @param a single space-separated list of C files (header or source)
# @example $(call ci, tidy, file1.c file2.c file3.h)

tidy:
	@$(CLANG-TIDY) --config-file=$(ci_dir)/.clang-tidy $(_tidy_files) -- \
		--target=$(clang-arch) $(CPPFLAGS) 2> /dev/null

.PHONY: tidy
non_build_targets+=tidy

define tidy
_tidy_files+=$1
endef

#############################################################################

# Cppcheck static-analyzer
# Run it by:
#    make cppcheck
# @param a single space-separated list of C files (header or source)
# @example $(call ci, cppcheck, file1.c file2.c file3.h)

cppcheck_type_cfg:=$(ci_dir)/.cppcheck-types.cfg
cppcheck_type_cfg_src:=$(ci_dir)/cppcheck-types.c

$(cppcheck_type_cfg): $(cppcheck_type_cfg_src)
	@$(cc) -S -o - $< | grep "\->" | sed -r 's/.*->//g' > $@

cppcheck_suppressions:=$(ci_dir)/.cppcheck-suppress
cppcheck_flags:= --quiet --enable=all --error-exitcode=1 \
	--library=$(cppcheck_type_cfg) \
	--suppressions-list=$(cppcheck_suppressions) $(CPPFLAGS)

cppcheck: $(cppcheck_type_cfg)
	@$(CPPCHECK) $(cppcheck_flags) $(_cppcheck_files)

cppcheck-clean:
	@rm -f $(cppcheck_type_cfg)

clean: cppcheck-clean

.PHONY: cppcheck
non_build_targets+=cppcheck cppcheck-clean

define cppcheck
_cppcheck_files+=$1
endef

#############################################################################

# MISRA Checker
# Use this rule to run the Cppcheck misra add-on checker:
#    make misra-check
# @pre MISRA checker rules assume your repository as a misra folder in the
#    top-level directories with the records and permits subdirectories (see doc).
# @arg space separated list of C source files
# @arg space separated list of C header files
# @example $(call ci, misra, file1.c file2.c, file3.h)

misra_ci_dir:=$(ci_dir)/misra
misra_rules:=$(misra_ci_dir)/rules.txt
misra_cppcheck_supressions:=$(misra_ci_dir)/.cppcheck-misra-unused-checks
misra_deviation_suppressions:=$(misra_ci_dir)/.cppcheck-misra-deviations
misra_deviation_suppressions_script:=$(misra_ci_dir)/deviation_suppression.py
misra_suppresions:=$(misra_ci_dir)/.cppcheck-misra-suppressions

misra_dir:=$(root_dir)/misra
misra_deviation_records:=$(misra_dir)/deviations/
misra_deviation_permits:=$(misra_dir)/permits/

define cppcheck_misra_addon
"{\
    \"script\": \"misra\",\
    \"args\": [\
        \"--rule-texts=ci/misra/rules.txt\"\
    ]\
}"
endef

cppcheck_misra_flags:= --quiet --enable=all --error-exitcode=1 \
	--library=$(cppcheck_type_cfg) --addon=$(cppcheck_misra_addon) $(CPPFLAGS) \
	--suppressions-list=$(misra_suppresions)
zephyr_coding_guidelines:=https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/main/doc/contribute/coding_guidelines/index.rst


ifeq ($(MISRA_C2012_GUIDELINES),)
$(misra_rules):
	@echo "Appendix A Summary of guidelines" > $@
	-@wget -q -O - $(zephyr_coding_guidelines) | \
		grep "\* -  Rule" -A 2 | sed -n '2~2!s/\(.\{9\}\)//p' >> $@
else
$(misra_rules):
	@pdftotext $(MISRA_C2012_GUIDELINES) $@
endif

$(misra_deviation_suppressions): $$(_misra_c_files) $$(_misra_h_files)
	@$(misra_deviation_suppressions_script) $^ > $@

$(misra_suppresions): $(misra_cppcheck_supressions) $(misra_deviation_suppressions)
	@cat $^ > $@

misra-check: $(misra_rules) $(cppcheck_type_cfg) $(misra_suppresions)
	@$(CPPCHECK) $(cppcheck_misra_flags) $(_misra_c_files)

misra-clean:
	-rm -f $(misra_rules) $(misra_suppresions) $(misra_deviation_suppressions)

$(call ci, yamllint, $(wildcard $(misra_deviation_records) $(misra_deviation_permits)))

clean: misra-clean cppcheck-clean

.PHONY: misra-check misra-clean misra-dev-check
non_build_targets+=misra-check misra-clean

define misra
_misra_c_files+=$1
_misra_h_files+=$2
endef

#############################################################################

ci=$(eval $(call $1, $2, $3, $4, $5, $6, $7, $8, $9))

.PHONY: build
build:

.PHONY: base-ci
base-ci: format build cppcheck tidy misra-check
