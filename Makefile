APP_NAME = Glance
SWIFT_FILE = main.swift

.PHONY: build run clean

build:
	swiftc $(SWIFT_FILE) -o $(APP_NAME) -framework AppKit -framework ApplicationServices -framework Carbon

run: build
	./$(APP_NAME)

clean:
	rm -f $(APP_NAME)
