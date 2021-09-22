rsbench:pascal_config_offload.yaml
	./harness.py -i $< -b -p RSBench
run:pascal_config_offload.yaml
	./harness.py -i $< -r -p RSBench
clean: pascal_config_offload.yaml
	./harness.py -i $< -c -p RSBench
