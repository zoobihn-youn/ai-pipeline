def average(numbers):
    # Intentional bug for review test: no empty-list check (ZeroDivisionError).
    return sum(numbers) / len(numbers)


if __name__ == "__main__":
    print(average([1, 2, 3]))
