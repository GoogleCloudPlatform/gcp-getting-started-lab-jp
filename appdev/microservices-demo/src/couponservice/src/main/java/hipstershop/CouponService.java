/*
 * Copyright 2020, Google LLC.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package hipstershop;

import hipstershop.Demo.Coupon;
import hipstershop.Demo.CouponRequest;
import hipstershop.Demo.CouponResponse;
import io.grpc.Server;
import io.grpc.ServerBuilder;
import io.grpc.StatusRuntimeException;
import io.grpc.health.v1.HealthCheckResponse.ServingStatus;
import io.grpc.services.*;
import io.grpc.stub.StreamObserver;
import io.opencensus.common.Duration;
import io.opencensus.contrib.grpc.metrics.RpcViews;
import io.opencensus.exporter.stats.stackdriver.StackdriverStatsConfiguration;
import io.opencensus.exporter.stats.stackdriver.StackdriverStatsExporter;
import io.opencensus.exporter.trace.stackdriver.StackdriverTraceConfiguration;
import io.opencensus.exporter.trace.stackdriver.StackdriverTraceExporter;
import io.opencensus.trace.AttributeValue;
import io.opencensus.trace.Span;
import io.opencensus.trace.Tracer;
import io.opencensus.trace.Tracing;
import java.io.IOException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.concurrent.TimeUnit;

import com.google.common.collect.ImmutableMap;

import com.google.cloud.spanner.DatabaseClient;
import com.google.cloud.spanner.DatabaseId;
import com.google.cloud.spanner.ErrorCode;
import com.google.cloud.spanner.ResultSet;
import com.google.cloud.spanner.Spanner;
import com.google.cloud.spanner.SpannerOptions;
import com.google.cloud.spanner.Statement;

import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

public final class CouponService {

  private static final Logger logger = LogManager.getLogger(CouponService.class);
  private static final Tracer tracer = Tracing.getTracer();

  private Server server;
  private HealthStatusManager healthMgr;

  private static final CouponService service = new CouponService();

  private void start() throws IOException {
    int port = Integer.parseInt(System.getenv("PORT"));
    healthMgr = new HealthStatusManager();

    server =
        ServerBuilder.forPort(port)
            .addService(new CouponServiceImpl())
            .addService(healthMgr.getHealthService())
            .build()
            .start();
    logger.info("Coupon Service started, listening on " + port);
    Runtime.getRuntime()
        .addShutdownHook(
            new Thread() {
              @Override
              public void run() {
                // Use stderr here since the logger may have been reset by its JVM shutdown hook.
                System.err.println("*** shutting down gRPC Coupon server since JVM is shutting down");
                CouponService.this.stop();
                System.err.println("*** server shut down");
              }
            });
    healthMgr.setStatus("", ServingStatus.SERVING);
  }

  private void stop() {
    if (server != null) {
      healthMgr.clearStatus("");
      server.shutdown();
    }
  }

  private static class CouponServiceImpl extends hipstershop.CouponServiceGrpc.CouponServiceImplBase {

    /**
     * Retrieves ads based on context provided in the request {@code CouponRequest}.
     *
     * @param req the request containing context.
     * @param responseObserver the stream observer which gets notified with the value of {@code
     *     CouponResponse}
     */
    @Override
    public void getCoupons(CouponRequest req, StreamObserver<CouponResponse> responseObserver) {
      CouponService service = CouponService.getInstance();
      Span span = tracer.getCurrentSpan();
      try {
        span.putAttribute("method", AttributeValue.stringAttributeValue("getCoupons"));
        List<Coupon> allCoupons = new ArrayList<>();
        logger.info("session_id=" + req.getSessionId());

        if (!req.getSessionId().isEmpty()) {
          span.addAnnotation(
              "Creating Coupons using session_id",
              ImmutableMap.of(
                  "session_id",
                  AttributeValue.stringAttributeValue(req.getSessionId())));
          /* @TODO comment out below line at section 3. */
          Collection<Coupon> coupons = service.getCouponsBySessionId(req.getSessionId());
          /* @TODO comment in below line at section 3.
          Collection<Coupon> coupons = service.getCouponsBySessionIdWithSpanner(req.getSessionId());
          */
          allCoupons.addAll(coupons);
        } else {
          span.addAnnotation("No session_id provided.");
        }

        CouponResponse reply = CouponResponse.newBuilder().addAllCoupons(allCoupons).build();
        responseObserver.onNext(reply);
        responseObserver.onCompleted();
      } catch (StatusRuntimeException e) {
        logger.log(Level.WARN, "GetCoupon Failed", e.getStatus());
        responseObserver.onError(e);
      }
    }
  }

  private Collection<Coupon> getCouponsBySessionId(String sessionId){
    Collection<Coupon> coupons = new ArrayList<Coupon>();
    String hexSessionId = sessionId.replace("-", "");
    long expiredBy = Instant.now().plus(1, ChronoUnit.HOURS).getEpochSecond();

    if (hexSessionId.matches("[0-9a-f]{31}[0-9]$")){
      Coupon coupon =
        Coupon.newBuilder()
          .setCouponId("11111111-1111-1111-1111-111111111111")
          .setDiscountPercentage(15)
          .setIsUsed(false)
          .setExpiredBy(expiredBy)
          .build();
      coupons.add(coupon);
    }else if(hexSessionId.matches("[0-9a-f]{31}[a-f]$")){
      Coupon coupon =
        Coupon.newBuilder()
          .setCouponId("22222222-2222-2222-2222-222222222222")
          .setDiscountPercentage(30)
          .setIsUsed(false)
          .setExpiredBy(expiredBy)
          .build();
      coupons.add(coupon);
    }else{
      logger.error("Looks session_id's format is not Hexadecimal: " + sessionId);
    }
    return coupons;
  }

  private Collection<Coupon> getCouponsBySessionIdWithSpanner(String sessionId){
    Collection<Coupon> coupons = new ArrayList<Coupon>();

    SpannerOptions options = SpannerOptions.newBuilder().build();
    Spanner spanner = options.getService();

    final String instanceId = "appdev-handson-instance";
    final String databaseId = "appdev-db";

    try {
      // Creates a database client
      DatabaseClient dbClient = spanner.getDatabaseClient(DatabaseId.of(
          options.getProjectId(), instanceId, databaseId));
      // Queries the database
      Statement statement =
        Statement.newBuilder(
            "SELECT SessionId, CouponId, DiscountPercentage, IsUsed, ExpiredBy "
                + "FROM Coupons "
                + "WHERE SessionId = @sessionId")
          .bind("sessionId")
          .to(sessionId)
          .build();
      ResultSet resultSet = dbClient.singleUse().executeQuery(statement);
      try{
        while (resultSet.next()) {
          Coupon coupon =
            Coupon.newBuilder()
              .setCouponId(resultSet.getString("CouponId"))
              .setDiscountPercentage(Math.round(resultSet.getLong("DiscountPercentage")))
              .setIsUsed(resultSet.getBoolean("IsUsed"))
              .setExpiredBy(Math.round(resultSet.getLong("ExpiredBy")))
              .build();
          coupons.add(coupon);
          logger.info("Find coupon with session_id=" + sessionId + " result=" + coupon.toString());
        }
      }catch (com.google.cloud.spanner.SpannerException se){
        if (se.getErrorCode() == ErrorCode.INVALID_ARGUMENT){
          // Error codes can be found on https://cloud.google.com/spanner/docs/reference/rest/v1/Code
          logger.error("Query failed by Syntax error or so : " + se.getCause());
        } else{
          logger.error("Unexpected error : " + se.getCause());
        }
      }
    } finally {
      spanner.close();
    }
    return coupons;
  }

  private static CouponService getInstance() {
    return service;
  }

  /** Await termination on the main thread since the grpc library uses daemon threads. */
  private void blockUntilShutdown() throws InterruptedException {
    if (server != null) {
      server.awaitTermination();
    }
  }

  private static void initStackdriver() {
    logger.info("Initialize StackDriver");

    long sleepTime = 10; /* seconds */
    int maxAttempts = 5;
    boolean statsExporterRegistered = false;
    boolean traceExporterRegistered = false;

    for (int i = 0; i < maxAttempts; i++) {
      try {
        if (!traceExporterRegistered) {
          StackdriverTraceExporter.createAndRegister(
              StackdriverTraceConfiguration.builder().build());
          traceExporterRegistered = true;
        }
        if (!statsExporterRegistered) {
          StackdriverStatsExporter.createAndRegister(
              StackdriverStatsConfiguration.builder()
                  .setExportInterval(Duration.create(60, 0))
                  .build());
          statsExporterRegistered = true;
        }
      } catch (Exception e) {
        if (i == (maxAttempts - 1)) {
          logger.log(
              Level.WARN,
              "Failed to register Stackdriver Exporter."
                  + " Tracing and Stats data will not reported to Stackdriver. Error message: "
                  + e.toString());
        } else {
          logger.info("Attempt to register Stackdriver Exporter in " + sleepTime + " seconds ");
          try {
            Thread.sleep(TimeUnit.SECONDS.toMillis(sleepTime));
          } catch (Exception se) {
            logger.log(Level.WARN, "Exception while sleeping" + se.toString());
          }
        }
      }
    }
    logger.info("StackDriver initialization complete.");
  }

  /** Main launches the server from the command line. */
  public static void main(String[] args) throws IOException, InterruptedException {
    // Registers all RPC views.
    RpcViews.registerAllGrpcViews();

    new Thread(
            new Runnable() {
              public void run() {
                initStackdriver();
              }
            })
        .start();

    // Start the RPC server. You shouldn't see any output from gRPC before this.
    logger.info("CouponService starting.");
    final CouponService service = CouponService.getInstance();
    service.start();
    service.blockUntilShutdown();
  }
}
