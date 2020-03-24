# Coupon Service

The Coupon service provides advertisement based on context keys. If no context keys are provided then it returns random ads.

## Building locally

The Coupon service uses gradlew to compile/install/distribute. Gradle wrapper is already part of the source code. To build Ad Service, run:

```
./gradlew installDist
```
It will create executable script src/couponservice/build/install/hipstershop/bin/CouponService

### Upgrading gradle version
If you need to upgrade the version of gradle then run

```
./gradlew wrapper --gradle-version <new-version>
```

## Building docker image

From the repository root, run:

```
docker build --file src/couponservice/Dockerfile .
```

