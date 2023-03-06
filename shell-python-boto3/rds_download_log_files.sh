dbidentifier="${1:-read-replica-testing-shangupta-13}"
profile="${2:-dev-long-term-mfa}"
logpath="${3:-./$dbidentifier/postgres_$dbidentifier.log}"

rm -rf ./$dbidentifier 
mkdir ./$dbidentifier

echo "DB: $dbidentifier, Profile:$profile, LogPath:$logpath"
rm -f $logpath


logsfrom=$(date -v-2H -v-11M '+%s' && echo $EPOCHSECONDS)
for awsfilename in $( aws rds describe-db-log-files \
    --db-instance-identifier $dbidentifier 
    --file-last-written $logsfrom \
    --profile $profile | jq -r '.DescribeDBLogFiles[] | .LogFileName' 
)
do
    echo "Downloading $awsfilename"
    # localfilename=$(echo $awsfilename | cut -d '/' -f 2)
    # logpath="${3:-./$dbidentifier/$localfilename.log}"
    aws rds download-db-log-file-portion \
        --db-instance-identifier $dbidentifier \
        --starting-token 0 \
        --output text \
        --log-file $awsfilename \
        --profile $profile >> $logpath
    chmod 755 $logpath
    sleep 2s # add delay to avoid aws throttling
done

#git clone https://github.com/darold/pgbadger.git

# ~/Documents/git/pgbadger/pgbadger \
#     $(pwd)/$dbidentifier/postgres* \
#     -o $(pwd)/$dbidentifier/report.html