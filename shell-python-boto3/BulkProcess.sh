#!/bin/bash

#rm -f ./output/*.out
sleep 1s

while IFS=',' read -ra line;do
    server=$(echo "${line[0]}" | xargs)
    severity=$(echo "${line[1]}" | xargs)
    engineVersion=$(echo "${line[2]}" | xargs)
    environment=$(echo "${line[3]}" | xargs)

    if [[ $server != \#* ]]
    then
        instance=$server
        profile=$environment-long-term-mfa
        output=json
        severity=$severity
        echo "Processing - $server, $profile, $output, $severity, $engineVersion "
        ./rds-upgrade.sh $instance $profile $engineVersion $severity $output &
    else
        echo "Skipping - $server"
    fi
done < rds.txt