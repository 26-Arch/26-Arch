.DEFAULT_GOAL := no_arguments

no_arguments:
	@echo "Please specify a target to build"
	@echo "  - init: Initialize submodules"
	@echo "  - handin: Create a zip file for handin"
	@echo "  - test-lab1: Run lab1 test"

init:
	git submodule update --init --recursive

handin:
	@if [ ! -f docs/report.pdf ]; then \
		echo "Please write your report in the 'docs' folder and convert it to 'report.pdf' first"; \
		exit 1; \
	fi; \
	if [ ! -d vivado/test-cpu/project/project_3 ]; then \
		echo "Missing vivado/test-cpu/project/project_3, cannot package project_3"; \
		exit 1; \
	fi; \
	echo "Packing vivado/test-cpu/project/project_3 -> docs/project_3.zip"; \
	rm -f docs/project_3.zip; \
	zip -q -r docs/project_3.zip vivado/test-cpu/project/project_3; \
	echo "docs/project_3.zip ready"; \
	echo "Please enter your 'student id-name' (e.g., 12345678910-someone)"; \
	read filename; \
	echo "Please enter lab number (e.g., 1)"; \
	read lab_n; \
	zip -q -r "docs/$$filename-lab$$lab_n.zip" \
	  include vsrc docs/report.pdf docs/project_3.zip; \
	echo "Done: docs/$$filename-lab$$lab_n.zip";

sim-verilog:
	@echo "I don't know why, just make difftest happy..."

# DIFFTEST_OPTS = DELAY=0 # remove on lab 2

emu:
	$(MAKE) -C ./difftest emu $(DIFFTEST_OPTS)

export NOOP_HOME=$(abspath .)
export NEMU_HOME=$(abspath ./ready-to-run)

sim:
	rm -rf build
	mkdir -p build
	make EMU_TRACE=1 emu -j12 NOOP_HOME=$(NOOP_HOME) NEMU_HOME=$(NEMU_HOME)

test-lab1: sim
	TEST=$(TEST) ./build/emu --diff $(NEMU_HOME)/riscv64-nemu-interpreter-so -i ./ready-to-run/lab1/lab1-test.bin $(VOPT) || true

test-lab1-extra: sim
	TEST=$(TEST) ./build/emu --diff $(NEMU_HOME)/riscv64-nemu-interpreter-so -i ./ready-to-run/lab1/lab1-extra-test.bin $(VOPT) || true

test-lab2: sim
	TEST=$(TEST) ./build/emu --diff $(NEMU_HOME)/riscv64-nemu-interpreter-so -i ./ready-to-run/lab2/lab2-test.bin $(VOPT) || true

test-lab3: sim
	TEST=$(TEST) ./build/emu --diff $(NEMU_HOME)/riscv64-nemu-interpreter-so -i ./ready-to-run/lab3/lab3-test.bin $(VOPT) || true

test-lab3-extra: sim
	TEST=$(TEST) ./build/emu --diff $(NEMU_HOME)/riscv64-nemu-interpreter-so -i ./ready-to-run/lab3/lab3-extra-test.bin $(VOPT) || true

test-lab4: sim
	TEST=$(TEST) ./build/emu --diff $(NEMU_HOME)/riscv64-nemu-interpreter-so -i ./ready-to-run/lab4/lab4-test.bin $(VOPT) || true

clean:
	rm -rf build

include verilate/Makefile.include
include verilate/Makefile.verilate.mk
include verilate/Makefile.vsim.mk

.PHONY: emu clean sim
