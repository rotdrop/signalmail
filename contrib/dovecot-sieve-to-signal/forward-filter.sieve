require ["fileinto","variables","vnd.dovecot.execute","editheader","copy"];
# rule:[variable-from]
if header :matches "from" "*"
{
  set "sender_from" "${1}";
}
# rule:[variable-to]
if header :matches "To" "*"
{
  set "recipient" "${1}";
}
# rule:[signal-sync-forward]
# Pipe to signal-forwarder if it was not in turn forwarded to the list from signal
#
if allof (header :contains "list-id" "signal-sync.lists.example.tld", not exists "X-Signal-Forwarded", not header :contains "from" "signal-sync-bounces@lists.example.tld")
{
  if execute :pipe :output "signal_response" "signal-gateway" ["${sender_from}", "${recipient}"]
  {
    addheader "X-Forwarded-To-Signal" "${signal_response}";
  } else {
    addheader "X-Forwarded-To-Signal" "FAILED ${signal_response}";
  }
}
# rule:[signal-sync-to-mailing-list]
if allof (header :is "X-Signal-Group-Name" "cafev-group-test", not header :is "X-Signal-Forwarded-To" "signal-sync@lists.example.tld")
{
  addheader "X-Signal-Forwarded-To" "signal-sync@lists.example.tld";
  deleteheader "Delivered-To";
  deleteheader "To";
  addheader "To" "signal-sync@lists.example.tld";
  deleteheader "DKIM-Signature";
  redirect "signal-sync@lists.example.tld";
  stop;
}
# rule:[signal-sync-move]
if allof (header :contains "list-id" "signal-sync.lists.example.tld")
{
  fileinto "signal-sync-test";
  stop;
}
