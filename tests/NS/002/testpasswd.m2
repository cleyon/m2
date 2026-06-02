@import passwd ns_passwd.lib
@set pw @getpwent@
@while @len pw@ > 0
@pw@
@set pw @getpwent@
@wend
