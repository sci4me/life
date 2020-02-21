BINARY=life
SRC_DIR=src
ODIN_BINARY=$(shell which odin)
ODIN_DIR=$(shell dirname $(ODIN_BINARY))
CXXFLAGS=

.PHONY: all clean run

all: release

release: clean
release: CXXFLAGS+=-opt=3
release: $(BINARY)

debug: clean
debug: CXXFLAGS+=-opt=0 -debug
debug: $(BINARY)

clean:
	rm -f $(BINARY)

$(BINARY):
	$(ODIN_DIR)/odin build $(SRC_DIR) $(CXXFLAGS) -out=$(BINARY)

run: debug
	./$(BINARY)