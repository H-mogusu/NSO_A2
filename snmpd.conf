#!/bin/bash

# OpenStack image list command with filtering
. $1


getSuitableImage() {
    local found=false    
    openstack image list --format json | \
    jq -r '.[] | select(.Name | test("(?i)ubuntu.*20")) | "\(.ID) \(.Name)"' | \
    while read -r image_id image_name; do
        echo $image_id
   done

}

# Call the function
IMAGE_ID=$(getSuitableImage)
echo $IMAGE_ID
