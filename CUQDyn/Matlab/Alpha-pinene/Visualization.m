% Visualization

for i=1:n    
    times = data_matrix(:,1);
    observed_values = data_matrix(:,i+1);
    predicted_values = solution_tot(:,i+1);
    low_b = regionsi(:,i); % Lower bounds
    up_b = regionss(:,i); % Upper bounds
    
    figure;
    
    % Plot of the upper bounds line
    plot(times, up_b, '-','Color',[0.5 0.5 0.5], 'LineWidth', 2);
    hold on;
    
    % Plot of the lower bounds line
    plot(times, low_b, '-','Color',[0.5 0.5 0.5], 'LineWidth', 2);
    
    fill([times; flipud(times)], [up_b; flipud(low_b)], [0.8 0.8 0.8], 'EdgeColor', 'none');

    % Plot of the predicted values
    plot(times, predicted_values, 'b--', 'LineWidth', 2);

     % Plot the observed data
    plot(times,observed_data(:,i),'.','MarkerSize', 20);

    % Labels
    xlabel('Time');
    ylabel('State value');
    titleStr = sprintf('Predictive Regions State %i', i);
    title(titleStr);
    legend('', '','Predictive region','Predicted values','Observed Values');
    grid on;
    hold off;
end
