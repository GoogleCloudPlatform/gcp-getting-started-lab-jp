# Nightly export schedule. NOTE: sta-cleanup-legacy deliberately has no
# rule/target here — its cron lived on a decommissioned ops box (see the
# handler docstring) and was never re-attached.

resource "aws_cloudwatch_event_rule" "daily_export" {
  name                = "${local.prefix}daily-export"
  description         = "Nightly task-reminder export to S3 (00:00 UTC)"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_target" "daily_export" {
  rule = aws_cloudwatch_event_rule.daily_export.name
  arn  = aws_lambda_function.fn["export_worker"].arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["export_worker"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_export.arn
}
