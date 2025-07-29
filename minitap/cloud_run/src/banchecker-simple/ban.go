package main

import (
	"bufio"
	"io"
	"os"
	"regexp"
	"strings"
)

var r *regexp.Regexp

const BanWordsFilename = "banwords.txt"

func init() {
	f, _ := os.Open(BanWordsFilename)
	defer f.Close()

	bu := bufio.NewReader(f)
	bannedWords := make([]string, 0)

	for {
		word, _, err := bu.ReadLine()
		if err == io.EOF {
			break
		}
		bannedWords = append(bannedWords, string(word))
	}
	bannedWordsRegex := strings.Join(bannedWords, "|")
	r, _ = regexp.Compile(bannedWordsRegex)
}

func IncludeBannedWords(text string) bool {
	return r.MatchString(text)
}
