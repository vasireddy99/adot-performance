This Script is used to run the performance analysis of the ADOT Collector and the Prometheus (agent mode).

The Configuration files under `/config` directory are hardcoded to a specific AMP endpoint, Please change the remote write endpoint as appropriate. 

Using the variables referred in [variables.tf](https://gitlab.aws.dev/adot/adot-performance/-/blob/main/variables.tf) file, arguments can be passed based on the use case. Variables such as `metric-load`, `label-count`, `series-interval` etc.,

Example to run the ADOT collector 
- `terraform apply --var=metric-load=5000 --var=collector=true -auto-approve`

Example to run the prometheus (Agent Mode)
- `terraform apply --var=metric-load=5000 --var=collector=false -auto-approve`

The Folder content under CwResponse, mocked_servers, mocks are invalid/unused for now at the moment, steps will be added later about these significance and on how to use these modules.
