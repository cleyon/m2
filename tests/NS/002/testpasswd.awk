BEGIN {
    while ((p = getpwent()) != "")
        print p
}
