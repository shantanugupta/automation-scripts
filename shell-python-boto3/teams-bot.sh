postMessage(){
    webhook="<teams-channel-webhook-url>";
    msg="'{\"text\": \"$1\"}'"
    command=$(echo "curl -H 'Content-Type: application/json' -d $msg $webhook;")
    echo $command;
    details=$(eval $command)
}
postMessage "Test script"