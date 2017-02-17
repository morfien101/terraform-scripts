# terraform-examples
Hosted here are some terraform scripts that I have written to help me learning how to use terraform and AWS.
These are all designed to be used with my Terraform runner. ( https://github.com/morfien101/terraform-runner )

## How to use these?
If you are going to use my files you will first need to update the remote backend for your Terraform state files. Please read the Readme file in the Terraform Runner repo if that does not yet make sense to you.

I used S3 but because we just wrap the Terraform binary you could/(should be able) to use any of the supported backends. This is not tested as I have only made use of S3.

Below is a example configuration file. As you can see there is 3 settings that you would need to change if you are using S3.

Remember that you need to create these buckets before starting this process.
There is plenty of documentation out there on that process. Use google.

__/config/aws_thing/thing.json__
```javascript
{
	"environment": "AWS Training",
	"tf_file_path":"scripts/aws_training_vpc",
	"variable_path":"scripts/aws_training_vpc",
	"variable_files":["vpc.tfvars"],
	"state_file":{
		"type":"s3",
		"config": {
			"region":"< Change Me!! >",
			"bucket":"< Change Me!! >",
			"key":" < Change Me!! > "
		}
	},
	"custom_args":["-parallelism=10"]
}
```
