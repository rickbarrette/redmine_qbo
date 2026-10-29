# Nickname data

`names.csv` is from the [nicknames](https://github.com/carltonnorthern/nicknames) project by
Carlton Northern and contributors (commit `ed160b3`), used under the Apache License 2.0
(see `LICENSE.txt`). It is unmodified.

Each row is `name1,has_nickname,name2`. `CustomerSearchService` uses it so that a search for
"Bill Smith" finds "William Smith". To update it, replace `names.csv` with a newer copy from the
project; extra name groups can also be added in `CustomerSearchService::EXTRA_NICKNAME_GROUPS`.
