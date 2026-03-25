SCHEME    := RawImg
CONFIG    := Debug
PROJ      := RawImg.xcodeproj
BUILD_DIR  = $(shell xcodebuild -project $(PROJ) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $$3}')
APP        = $(BUILD_DIR)/RawImg.app

.PHONY: build run all clean generate test

all: build run

generate:
	@xcodegen generate

build: generate
	@xcodebuild -project $(PROJ) -scheme $(SCHEME) -configuration $(CONFIG) build 2>&1 | tail -1

run:
	@open "$(APP)"

clean:
	@xcodebuild -project $(PROJ) -scheme $(SCHEME) -configuration $(CONFIG) clean 2>&1 | tail -1
	@rm -rf build

test:
	@cmake -B build -S . 2>&1 | tail -1
	@cmake --build build 2>&1 | tail -1
	@./build/core/rawimg-tests
