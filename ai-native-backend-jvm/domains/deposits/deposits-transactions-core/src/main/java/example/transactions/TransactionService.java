package example.transactions;

import example.achpse.AchPseLibrary;
import example.credibanco.CredibancoLibrary;
import example.fraud.DepositsFraudLibrary;
import example.neurona.NeuronaLibrary;
import example.sdk.TransactionsCoreApi;

public final class TransactionService {
    private TransactionService() {}

    public static void main(String[] args) {
        System.out.println(String.join(
            ",",
            AchPseLibrary.name(),
            CredibancoLibrary.name(),
            DepositsFraudLibrary.name(),
            TransactionsCoreApi.name(),
            NeuronaLibrary.name()
        ));
    }
}
