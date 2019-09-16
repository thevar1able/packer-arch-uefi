all: clean image

.PHONY: image
image:
	packer build arch.json

.PHONY: clean
clean:
	rm -rf output-qemu