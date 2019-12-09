/*
Copyright 2019 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"context"
	"fmt"
	"html/template"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"time"

	"cloud.google.com/go/profiler"
	"contrib.go.opencensus.io/exporter/stackdriver"
	log "github.com/sirupsen/logrus"
	"go.opencensus.io/trace"
	"golang.org/x/oauth2/google"
)

var projectID = ""

const (
	service        = "devops-demo"
	serviceVersion = "1.0.1"
	metricPrefix   = "devops-"
)

// A IndexVariables represents variables used in a template (index.html)
type IndexVariables struct {
	WebsiteTitle string
	RandomNumber string
}

func logRequest(r *http.Request, traceID string, spanID string, msg string) {
	log.WithFields(log.Fields{
		"UserAgent":                     r.UserAgent(),
		"RequestURL":                    r.Host,
		"RequestURI":                    r.RequestURI,
		"RequestMethod":                 r.Method,
		"Host":                          r.Host,
		"Proto":                         r.Proto,
		"ProtoMajor":                    r.ProtoMajor,
		"ProtoMinor":                    r.ProtoMinor,
		"RemoteAddr":                    r.RemoteAddr,
		"logging.googleapis.com/trace":  "projects/" + projectID + "/traces/" + traceID,
		"logging.googleapis.com/spanId": spanID,
	}).Info(msg)
}

func logMethod(traceID string, spanID string, msg string) {
	log.WithFields(log.Fields{
		"logging.googleapis.com/trace":  "projects/" + projectID + "/traces/" + traceID,
		"logging.googleapis.com/spanId": spanID,
	}).Info(msg)
}

func mainHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, span := trace.StartSpan(context.Background(), "/")
		defer span.End()
		s := span.SpanContext()

		addAttributesToSpan(span, r)
		logRequest(r, s.TraceID.String(), s.SpanID.String(), "Hello from mainHandler")

		iv := &IndexVariables{
			WebsiteTitle: "Main",
			RandomNumber: strconv.Itoa(rand.Intn(100)),
		}

		renderTemplate(w, iv)
	})
}

func benchHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, span := trace.StartSpan(context.Background(), "/bench1")
		defer span.End()
		s := span.SpanContext()

		addAttributesToSpan(span, r)
		logRequest(r, s.TraceID.String(), s.SpanID.String(), "Hello from benchHandler")

		// Stress
		fibonacci(ctx, rand.Intn(3000000000))
		fibonacci(ctx, rand.Intn(3000000000))
		fibonacci(ctx, rand.Intn(3000000000))

		iv := &IndexVariables{
			WebsiteTitle: "Bench",
			RandomNumber: strconv.Itoa(rand.Intn(100)),
		}
		renderTemplate(w, iv)
	})
}

func addAttributesToSpan(span *trace.Span, r *http.Request) {
	span.AddAttributes(
		trace.StringAttribute("Method", r.Method),
		trace.StringAttribute("Host", r.Host),
		trace.StringAttribute("Proto", r.Proto),
		trace.Int64Attribute("ProtoMajor", int64(r.ProtoMajor)),
		trace.Int64Attribute("ProtoMinor", int64(r.ProtoMinor)),
		trace.Int64Attribute("ContentLength", int64(r.ContentLength)),
		trace.StringAttribute("RequestURI", r.RequestURI),
		trace.StringAttribute("RemoteAddr", r.RemoteAddr),
		trace.StringAttribute("UserAgent", r.UserAgent()),
		trace.StringAttribute("Referer", r.Referer()),
	)
}

func waitRandomMilliseconds(ctx context.Context) {
	_, span := trace.StartSpan(ctx, "waitRandomMilliseconds")
	defer span.End()
	time.Sleep(time.Duration(rand.Intn(1000)) * time.Millisecond)
}

func fibonacci(ctx context.Context, loopNum int) {
	_, span := trace.StartSpan(ctx, "fibonacci")
	s := span.SpanContext()
	defer span.End()
	prev, next := 0, 1
	for i := 0; i < loopNum; i++ {
		prev, next = next, prev+next
	}
	span.AddAttributes(trace.Int64Attribute("loopNum", int64(loopNum)))

	logMethod(s.TraceID.String(), s.SpanID.String(), fmt.Sprintf("Fibonacci calculation completed: %v loops", loopNum))
}

var templates = template.Must(template.ParseFiles("./template/index.html"))

func renderTemplate(w http.ResponseWriter, iv *IndexVariables) {
	err := templates.Execute(w, iv)
	if err != nil {
		log.Printf("Failed to render a template: %v", err)
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func initLogSettings() {
	log.SetFormatter(&log.JSONFormatter{
		FieldMap: log.FieldMap{
			log.FieldKeyTime:  "time",
			log.FieldKeyLevel: "severity",
			log.FieldKeyMsg:   "message",
		},
		TimestampFormat: time.RFC3339Nano,
	})
	log.SetOutput(os.Stdout)
	log.SetLevel(log.InfoLevel)
}

func main() {
	rand.Seed(time.Now().UnixNano())

	initLogSettings()

	// Initialize the credential and projectID with Application Default Credentials (ADC)
	ctx := context.Background()
	cred, err := google.FindDefaultCredentials(ctx)
	if err != nil {
		log.Fatal(err.Error())
	}
	projectID = cred.ProjectID
	log.Infof("Successfully retrieved GCP Project ID: %v", projectID)

	// Initialize Profiler
	if err := profiler.Start(profiler.Config{
		Service:        service,
		ServiceVersion: serviceVersion,
		ProjectID:      projectID,
	}); err != nil {
		log.Fatal(err.Error())
	}
	log.Info("Successfully initialized profiler")

	// Initialize exporter
	exporter, err := stackdriver.NewExporter(stackdriver.Options{
		ProjectID:    projectID,
		MetricPrefix: metricPrefix,
	})
	if err != nil {
		log.Fatal(err.Error())
	}
	log.Info("Successfully initialized exporter")
	defer exporter.Flush()
	trace.RegisterExporter(exporter)
	trace.ApplyConfig(trace.Config{DefaultSampler: trace.AlwaysSample()})

	// Serve static files under /static/ directory
	http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("./static"))))

	// Register handlers
	http.Handle("/", mainHandler())
	http.Handle("/bench1", benchHandler())

	log.Info("Start listening : 8080...")
	http.ListenAndServe(":8080", nil)
}
