@#              Use default region if available
@if_env AWS_DEFAULT_REGION
@define region @getenv AWS_DEFAULT_REGION@
@endif
@#              If you want your own default region, uncomment
@default region us-west-2
@#              Otherwise, m2 will exit with error message
@ifndef region
@error You must provide a value for 'region' on the command line
@endif
@#              Validate region
@array valid_regions
@define valid_regions[us-east-1]
@define valid_regions[us-east-2]
@define valid_regions[us-west-1]
@define valid_regions[us-west-2]
@if_not_in @region@ valid_regions
@error Region '@region@' is not valid: choose us-{east,west}-{1,2}
@endif
@#              Configure image name according to region
@array images
@define images[us-east-1]   my-east1-image-name
@define images[us-east-2]   my-east2-image-name
@define images[us-west-1]   my-west1-image-name
@define images[us-west-2]   my-west2-image-name
@define my_image @images[@{region}]@
@#              Output begins here
Region: @region@
Image:  @my_image@
